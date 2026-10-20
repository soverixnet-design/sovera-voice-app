import io
import sqlite3
import tempfile
import unittest
from PIL import Image
from fastapi.testclient import TestClient
from .app import Profiles, ProfileInput, create_app

class ProfileMediaTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.profiles=Profiles(self.temp.name+'/test.sqlite3')
        async def verify(token):
            if token not in ('alice','bob'): raise ValueError()
            return token
        self.client=TestClient(create_app(self.profiles,verify))
        self.headers={'Authorization':'Bearer alice'}
    def tearDown(self): self.temp.cleanup()
    def test_optional_fields_and_old_client(self):
        data={'display_name':'Alice','country':'BD','gender':'female','birthday':'2000-01-02'}
        self.assertEqual(self.client.put('/sovera/account',headers=self.headers,json=data).status_code,200)
        self.profiles.save('alice',ProfileInput(display_name='New name',country='BD'))
        self.assertEqual(self.profiles.get('alice')['birthday'],'2000-01-02')
        data.update(gender=None,birthday=None)
        self.client.put('/sovera/account',headers=self.headers,json=data)
        self.assertIsNone(self.profiles.get('alice')['gender'])
        data['birthday']='2999-01-01'
        self.assertEqual(self.client.put('/sovera/account',headers=self.headers,json=data).status_code,422)
    def test_photo_auth_sanitizing_replacement(self):
        image=io.BytesIO();Image.new('RGB',(1200,900),'red').save(image,'PNG')
        url='/sovera/account/avatar'
        self.assertEqual(self.client.post(url,content=image.getvalue()).status_code,401)
        response=self.client.post(url,headers=self.headers,content=image.getvalue())
        self.assertEqual(response.status_code,200)
        photo=self.client.get(response.json()['avatar_url'].replace('https://voice.soverixnet.com',''))
        self.assertEqual(photo.headers['content-type'],'image/webp')
        with Image.open(io.BytesIO(photo.content)) as decoded:
            self.assertLessEqual(max(decoded.size),768)
            self.assertFalse(decoded.getexif())
        self.assertEqual(self.client.post(url,headers=self.headers,content=b'<svg/>').status_code,400)
        self.client.post(url,headers=self.headers,content=image.getvalue())
        with sqlite3.connect(self.profiles.path) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM account_avatar_photos').fetchone()[0],1)
