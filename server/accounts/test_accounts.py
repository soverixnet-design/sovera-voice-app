import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app

class AccountTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'profiles.db'
        self.store = Profiles(self.path)
        async def verify(token):
            if token not in ('alice','bob'): raise ValueError('secret SDK error')
            return token
        self.client = TestClient(create_app(self.store, verify))
        self.data = {'display_name':'Shakil','country':'BD','bio':'Hello'}

    def test_private_and_persistent(self):
        self.assertEqual(self.client.get('/sovera/account').status_code,401)
        self.assertEqual(self.client.put('/sovera/account',json=self.data,headers={'Authorization':'Bearer alice'}).status_code,200)
        self.assertEqual(Profiles(self.path).get('alice')['display_name'],'Shakil')
        response=self.client.get('/sovera/account',headers={'Authorization':'Bearer bob'})
        self.assertIsNone(response.json()['profile'])
        self.assertEqual(response.headers['cache-control'],'no-store')

    def test_reject_spoofed_identity_and_wallet(self):
        for key in ('firebase_uid','is_banned','role','coins','uid'):
            r=self.client.put('/sovera/account',json={**self.data,key:'owner'},headers={'Authorization':'Bearer alice'})
            self.assertEqual(r.status_code,422)
        self.assertIsNone(self.store.get('alice'))

    def test_invalid_sessions_and_media(self):
        r=self.client.get('/sovera/account',headers={'Authorization':'Bearer revoked'})
        self.assertEqual(r.status_code,401)
        self.assertNotIn('secret',r.text)
        for url in ('javascript:alert(1)','http://example.com/a','https://u:p@example.com/a'):
            r=self.client.put('/sovera/account',json={**self.data,'avatar_url':url},headers={'Authorization':'Bearer alice'})
            self.assertEqual(r.status_code,422)
        self.assertEqual(self.client.get('/sovera/account/health').json()['wallet'],False)

if __name__=='__main__': unittest.main()
