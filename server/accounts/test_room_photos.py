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

    def test_live_chat_photos_permissions_retry_and_room_settings(self):
        import uuid
        self.profiles.save('alice',ProfileInput(display_name='Alice',country='BD'))
        self.profiles.save('bob',ProfileInput(display_name='Bob',country='BD'))
        room=self.client.post('/sovera/account/rooms',headers=self.headers,json={'name':'Photos','seats':9}).json()['room']['id']
        root=f'/sovera/account/rooms/{room}'
        image=io.BytesIO();Image.new('RGB',(60,60),'red').save(image,'PNG')
        self.assertEqual(self.client.post(root+'/chat-photo',headers=self.headers,content=image.getvalue()).status_code,403)
        self.client.put(root+'/presence',headers=self.headers)
        photo=self.client.post(root+'/chat-photo',headers=self.headers,content=image.getvalue())
        self.assertEqual(photo.status_code,200)
        payload={'text':'','image_url':photo.json()['avatar_url'],'request_id':str(uuid.uuid4())}
        first=self.client.post(root+'/messages',headers=self.headers,json=payload)
        self.assertEqual(first.status_code,200)
        self.assertEqual(self.client.post(root+'/messages',headers=self.headers,json=payload).json(),first.json())
        items=self.client.get(root+'/messages',headers=self.headers).json()['messages']
        self.assertEqual(items[-1]['image_url'],payload['image_url'])
        self.assertEqual(self.client.post(root+'/messages',headers={'Authorization':'Bearer bob'},json={**payload,'request_id':str(uuid.uuid4())}).status_code,422)
        settings={'name':'Photos','seats':6,'theme':'ocean','chat_enabled':False,'photo_min_level':3}
        self.assertEqual(self.client.put(root,headers={'Authorization':'Bearer bob'},json=settings).status_code,403)
        self.assertEqual(self.client.put(root,headers=self.headers,json=settings).status_code,200)
        visible=self.client.get(root+'/controls',headers={'Authorization':'Bearer bob'}).json()['room']
        self.assertEqual(visible['theme'],'ocean');self.assertEqual(visible['photo_min_level'],3)
        self.assertEqual(self.client.post(root+'/messages',headers=self.headers,json={'text':'blocked','request_id':str(uuid.uuid4())}).status_code,403)
        self.assertEqual(self.client.post(root+'/chat-photo',headers=self.headers,content=image.getvalue()).status_code,403)
        # An already committed send can safely be retried after settings change.
        self.assertEqual(self.client.post(root+'/messages',headers=self.headers,json=payload).json(),first.json())

    def test_background_picture_is_owned_and_survives_cover_replacement(self):
        self.profiles.save('alice',ProfileInput(display_name='Alice',country='BD'))
        room=self.client.post('/sovera/account/rooms',headers=self.headers,json={'name':'Background','seats':9}).json()['room']['id']
        root=f'/sovera/account/rooms/{room}'
        image=io.BytesIO();Image.new('RGB',(50,50),'red').save(image,'PNG')
        url=self.client.post(root+'/photo',headers=self.headers,content=image.getvalue()).json()['avatar_url']
        self.assertEqual(self.client.put(root,headers=self.headers,json={'name':'Background','seats':9,'background_url':url}).status_code,200)
        image=io.BytesIO();Image.new('RGB',(50,50),'blue').save(image,'PNG')
        cover=self.client.post(root+'/photo',headers=self.headers,content=image.getvalue()).json()['avatar_url']
        self.client.put(root,headers=self.headers,json={'name':'Background','seats':9,'image_url':cover})
        self.assertEqual(self.client.get(url.replace('https://voice.soverixnet.com','')).status_code,200)
        state=self.client.get(root+'/controls',headers=self.headers).json()['room']
        self.assertEqual(state['background_url'],url)
        self.assertEqual(self.client.put(root,headers=self.headers,json={'name':'Background','seats':9,'background_url':'https://example.com/unowned.webp'}).status_code,422)
