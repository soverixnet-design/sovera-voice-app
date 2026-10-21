"""Critical prevention of game wallet bypass or identity spoofing."""
import base64
import hashlib
import hmac
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app
from server.accounts.greedy_access import greedy_access
from fastapi import HTTPException

class GreedyAccessTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.profiles=Profiles(Path(self.temp.name)/'db.sqlite3')
        async def verify(token):
            if token!='alice-token':raise ValueError('not authorized')
            return 'alice'
        self.client=TestClient(create_app(self.profiles,verify))
        self.headers={'Authorization':'Bearer alice-token'}
        self.identity={'firebase_uid':'alice','display_name':'Test User',
                       'country':'BD','bio':'','avatar_url':None}
    def test_disabled_with_no_wallet_even_when_signed_in(self):
        with patch.dict(os.environ,{},clear=True):
            self.assertEqual(self.client.post('/sovera/account/greedy/access').status_code,401)
            self.assertEqual(self.client.post('/sovera/account/greedy/access',
                headers=self.headers).status_code,409)
            self.profiles.save('alice',type('D',(),self.identity)())
            self.assertEqual(self.client.post('/sovera/account/greedy/access',
                headers=self.headers).status_code,503)
        self.assertEqual(self.client.post('/sovera/account/greedy/access',
            headers={'Authorization':'Bearer bad'}).status_code,401)
    def test_valid_token_bound_to_server_verified_identity(self):
        self.profiles.save('alice',type('D',(),self.identity)())
        env={'SOVERA_GREEDY_ENABLED':'1',
             'SOVERA_GREEDY_WALLET_VERIFIED':'1',
             'SOVERA_GREEDY_JWT_SECRET':'q'*42,
             'SOVERA_GREEDY_PUBLIC_URL':'https://voice.soverixnet.com/greedy/'}
        with patch.dict(os.environ,env,clear=True):
            # Client cannot bypass the as-yet-unmigrated authoritative wallet.
            response=self.client.post('/sovera/account/greedy/access',
                headers=self.headers)
            self.assertEqual(response.status_code,503)
            # Independently verify the game-only signed token encoder.
            body=greedy_access('alice',self.identity)
        self.assertEqual(body['game_url'],env['SOVERA_GREEDY_PUBLIC_URL'])
        parts=body['token'].split('.')
        self.assertEqual(len(parts),3)
        claimed=json.loads(base64.urlsafe_b64decode(parts[1]+'=='))
        self.assertEqual(claimed['uid'],'alice')
        self.assertEqual(claimed['name'],'Test User')
        self.assertEqual(claimed['exp']-claimed['iat'],300)
        mac=hmac.new(env['SOVERA_GREEDY_JWT_SECRET'].encode(),
                     (parts[0]+'.'+parts[1]).encode(),hashlib.sha256).digest()
        self.assertEqual(parts[2].rstrip('='),base64.urlsafe_b64encode(mac).decode().rstrip('='))
        self.assertNotIn('password',str(body).lower())
    def test_incomplete_config_never_issues_game_token(self):
        profile=dict(self.identity)
        good={'SOVERA_GREEDY_ENABLED':'1','SOVERA_GREEDY_WALLET_VERIFIED':'1',
              'SOVERA_GREEDY_JWT_SECRET':'a'*40,'SOVERA_GREEDY_PUBLIC_URL':'https://voice.soverixnet.com/greedy/'}
        for missing,broken in [('SOVERA_GREEDY_WALLET_VERIFIED','0'),
              ('SOVERA_GREEDY_JWT_SECRET','change-me'),
              ('SOVERA_GREEDY_PUBLIC_URL','http://localhost:8080/'),
              ('SOVERA_GREEDY_PUBLIC_URL','https://person:password@example.com/')]:
            with self.subTest(missing=missing),patch.dict(os.environ,{**good,missing:broken},clear=True):
                with self.assertRaises(HTTPException) as cm:
                    greedy_access('alice',profile)
                self.assertEqual(cm.exception.status_code,503)

if __name__=='__main__':
    unittest.main()
