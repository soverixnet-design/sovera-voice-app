import io
import unittest
from PIL import Image
from .test_profile_media import ProfileMediaTests
from .app import ProfileInput

class RoomPhotoTests(unittest.TestCase):
    setUp=ProfileMediaTests.setUp
    tearDown=ProfileMediaTests.tearDown
    def test_owner_photo_is_independent_persistent_and_not_assignable_to_another_room(self):
        for uid in ('alice','bob'):
            self.profiles.save(uid,ProfileInput(display_name=uid,country='BD',avatar_url='https://example.com/personal.webp'))
        def create(uid):
            return self.client.post('/sovera/account/rooms',headers={'Authorization':'Bearer '+uid},json={'name':uid+' room','seats':9}).json()['room']['id']
        room=create('alice');other=create('bob')
        data=io.BytesIO();Image.new('RGB',(1200,800),'blue').save(data,'PNG')
        path=f'/sovera/account/rooms/{room}/photo'
        self.assertEqual(self.client.post(path,content=data.getvalue()).status_code,401)
        self.assertEqual(self.client.post(path,headers={'Authorization':'Bearer bob'},content=data.getvalue()).status_code,403)
        result=self.client.post(path,headers=self.headers,content=data.getvalue())
        self.assertEqual(result.status_code,200)
        url=result.json()['avatar_url']
        payload={'name':'alice room','seats':9,'image_url':url}
        saved=self.client.put(f'/sovera/account/rooms/{room}',headers=self.headers,json=payload)
        self.assertEqual(saved.status_code,200)
        self.assertEqual(saved.json()['room']['image_url'],url)
        visible=self.client.get(f'/sovera/account/rooms/{room}/controls',headers={'Authorization':'Bearer bob'}).json()
        self.assertEqual(visible['room']['image_url'],url)
        self.assertEqual(self.profiles.get('alice')['avatar_url'],'https://example.com/personal.webp')
        self.assertEqual(self.client.put(f'/sovera/account/rooms/{other}',headers={'Authorization':'Bearer bob'},json=payload).status_code,422)
        self.client.put(f'/sovera/account/rooms/{room}',headers=self.headers,json={'name':'New name','seats':6})
        rooms=self.client.get('/sovera/account/rooms',headers=self.headers).json()['rooms']
        self.assertEqual(next(r for r in rooms if r['id']==room)['image_url'],url)
        photo=self.client.get(url.replace('https://voice.soverixnet.com',''))
        with Image.open(io.BytesIO(photo.content)) as image:
            self.assertLessEqual(max(image.size),768)
        self.assertEqual(self.client.post(path,headers=self.headers,content=b'<svg/>').status_code,400)
