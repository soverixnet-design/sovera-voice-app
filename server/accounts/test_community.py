import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path
from fastapi.testclient import TestClient
from server.accounts.app import Profiles, create_app
from server.accounts.community import Community

class CommunityTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'account.db'
        self.profiles=Profiles(self.path)
        async def verify(token):
            if token not in ('alice','bob','support','owner'):raise ValueError()
            return token
        self.client=TestClient(create_app(self.profiles,verify))
        for uid in ('alice','bob','support','owner'):
            self.client.put('/sovera/account',headers=self.auth(uid),json={'display_name':uid,'country':'BD','bio':''})
    def auth(self,uid):return {'Authorization':'Bearer '+uid}
    def post(self,section,uid='alice',**extra):
        return self.client.post('/sovera/account/community/'+section,headers=self.auth(uid),json={'text':'Hello','request_id':str(uuid.uuid4()),**extra})

    def test_report_retries_are_private_and_blocking_filters_members_and_moments(self):
        report={'target_kind':'user','target_id':'bob','reason':'Repeated harassment',
                'request_id':str(uuid.uuid4())}
        url='/sovera/account/community/report'
        self.assertEqual(self.client.post(url,json=report).status_code,401)
        first=self.client.post(url,headers=self.auth('alice'),json=report)
        self.assertEqual(first.status_code,200,first.text)
        self.assertEqual(self.client.post(url,headers=self.auth('alice'),json=report).json(),first.json())
        self.assertEqual(self.client.post(url,headers=self.auth('alice'),
            json={**report,'reason':'Different reason'}).status_code,409)
        self.assertEqual(Community(self.path).list('bob','support'),[])
        self.assertIn('Repeated harassment',Community(self.path).list('alice','support')[0]['text'])
        self.post('moments',uid='bob')
        block='/sovera/account/community/blocks/bob'
        self.assertEqual(self.client.put(block,headers=self.auth('alice')).status_code,200)
        self.assertEqual(Community(self.path).list('alice','moments'),[])
        self.assertNotIn('bob',[r['uid'] for r in Community(self.path).list('alice','members')])
        self.assertEqual(Community(self.path).list('bob','blocks'),[])
        self.assertEqual(self.client.delete(block,headers=self.auth('alice')).status_code,200)
        self.assertEqual(len(Community(self.path).list('alice','moments')),1)

    def test_auth_and_moments_survive_restart_without_fake_authorship(self):
        self.assertEqual(self.client.get('/sovera/account/community/moments').status_code,401)
        self.assertEqual(self.post('moments',uid='alice',firebase_uid='bob').status_code,422)
        request={'text':'A real saved moment','request_id':str(uuid.uuid4())}
        for _ in range(2):
            self.assertEqual(self.client.post('/sovera/account/community/moments',headers=self.auth('alice'),json=request).status_code,200)
        rows=Community(self.path).list('bob','moments')
        self.assertEqual(len(rows),1)
        self.assertEqual((rows[0]['uid'],rows[0]['text']),('alice',request['text']))
        changed=self.client.post('/sovera/account/community/moments',headers=self.auth('alice'),json={**request,'text':'Changed'})
        self.assertEqual(changed.status_code,409)
        self.assertEqual(self.post('moments').status_code,429)

    def test_support_is_private_and_only_staff_can_reply(self):
        ticket=self.post('support').json()['id']
        self.assertEqual(Community(self.path).list('bob','support'),[])
        self.assertEqual(self.client.get('/sovera/account/staff/support',headers=self.auth('bob')).status_code,403)
        reply={'text':'We are checking','request_id':str(uuid.uuid4())}
        url=f'/sovera/account/staff/support/{ticket}'
        self.assertEqual(self.client.put(url,headers=self.auth('bob'),json=reply).status_code,403)
        with sqlite3.connect(self.path) as db:db.execute("INSERT INTO account_staff VALUES('support','support')")
        self.assertEqual(self.client.put(url,headers=self.auth('support'),json=reply).status_code,200)
        self.assertEqual(Community(self.path).list('alice','support')[0]['reply'],reply['text'])

    def test_no_auto_admin_and_publications_require_publisher(self):
        self.assertIsNone(self.client.get('/sovera/account/staff',headers=self.auth('alice')).json()['role'])
        publication={'title':'Room event','text':'Community gathering','section':'events','request_id':str(uuid.uuid4())}
        url='/sovera/account/staff/publications'
        self.assertEqual(self.client.post(url,headers=self.auth('alice'),json=publication).status_code,403)
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_staff VALUES('support','support')")
            db.execute("INSERT INTO account_staff VALUES('owner','owner')")
        self.assertEqual(self.client.post(url,headers=self.auth('support'),json=publication).status_code,403)
        for _ in range(2):self.assertEqual(self.client.post(url,headers=self.auth('owner'),json=publication).status_code,200)
        self.assertEqual(len(Community(self.path).list('alice','events')),1)

    def test_follows_private_persistent_and_idempotent(self):
        room=self.client.post('/sovera/account/rooms',headers=self.auth('bob'),json={'name':'Room'}).json()['room']['id']
        url='/sovera/account/community/follows/'+room
        for _ in range(2):self.assertEqual(self.client.put(url,headers=self.auth('alice')).status_code,200)
        self.assertEqual(Community(self.path).list('alice','follows'),[{'room':room}])
        self.assertEqual(Community(self.path).list('bob','follows'),[])
        for _ in range(2):self.assertEqual(self.client.delete(url,headers=self.auth('alice')).status_code,200)
        self.assertEqual(Community(self.path).list('alice','follows'),[])
        self.assertEqual(self.client.put('/sovera/account/community/follows/missing',headers=self.auth('alice')).status_code,404)

if __name__=='__main__':unittest.main()
