import io
import sqlite3
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
from fastapi import HTTPException
from . import test_control
from .catalog import Catalog,ItemInput,GrantInput,SelectInput,BuyInput,GiftInput
from .rooms import Rooms,RoomInput

class CatalogTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    login=test_control.ControlTests.login
    def setup_catalog(self):
        self.catalog=Catalog(self.path)
        data=io.BytesIO();Image.new('RGBA',(32,32),(255,0,0,0)).save(data,format='PNG')
        self.media=self.catalog.upload('owner',data.getvalue())
    def item(self,kind='frame',price=0):
        return self.catalog.save('owner',ItemInput(id=uuid.uuid4(),kind=kind,title='Test '+kind,media_id=self.media['id'],price=price))
    def seed_owner(self):
        with self.control.db() as db:
            db.execute("INSERT INTO account_wallet_links VALUES('owner','legacy-owner',1,'active')")
            db.execute("INSERT INTO account_wallet_ledger VALUES('seed-owner','owner',100,0,'verified_import',1)")
        rooms=Rooms(self.path);room=rooms.save('owner',RoomInput(name='Test room'))['id']
        for uid in ('owner','alice','support'):rooms.presence(uid,room)
        return room
    def test_gallery_upload_permissions_validation_and_animation(self):
        self.setup_catalog();self.login()
        headers={'Origin':'https://admin.soverixnet.com'}
        self.assertEqual(self.client.post('/sovera/control/media',content=b'<svg></svg>',headers=headers).status_code,400)
        self.assertEqual(self.client.post('/sovera/control/media',content=b'x',headers=headers|{'content-length':'9000000'}).status_code,413)
        self.assertEqual([r['uid'] for r in self.control.users('owner','legacy-alice')],['alice'])
        self.assertEqual(self.control.users('owner','legacy-alice',1),[])
        with self.assertRaises(HTTPException):self.catalog.upload('support',b'bad')
        data=io.BytesIO();Image.new('RGB',(32,32),'red').save(data,format='GIF',save_all=True,append_images=[Image.new('RGB',(32,32),'blue')],duration=100,loop=0)
        result=self.client.post('/sovera/control/media',content=data.getvalue(),headers=headers)
        self.assertEqual(result.status_code,200,result.text);self.assertEqual(result.json()['frames'],2)
        image=self.client.get('/sovera/account/media/'+result.json()['id'])
        self.assertEqual(image.headers['content-type'],'image/gif');self.assertEqual(image.content,data.getvalue())
    def test_low_data_preview_is_one_small_frame_and_private_data_is_not_cached(self):
        self.setup_catalog()
        data=io.BytesIO()
        Image.new('RGB',(800,400),'red').save(data,format='GIF',save_all=True,
            append_images=[Image.new('RGB',(800,400),'blue')],duration=100,loop=0)
        media=self.catalog.upload('owner',data.getvalue())
        response=self.client.get('/sovera/account/media/'+media['id']+'?still=true')
        self.assertEqual(response.status_code,200)
        self.assertIn('immutable',response.headers['cache-control'])
        with Image.open(io.BytesIO(response.content)) as image:
            self.assertEqual(image.size,(384,192))
            self.assertEqual(getattr(image,'n_frames',1),1)
        private=self.client.get('/sovera/account',headers={'Authorization':'Bearer alice'})
        self.assertEqual(private.headers['cache-control'],'no-store')

    def test_default_animated_gifts_are_seeded_once_and_keep_owner_changes(self):
        from .seed_gifts import seed
        first=seed(self.path)
        self.assertEqual(first['added'],16)
        catalog=Catalog(self.path)
        items=[x for x in catalog.listing('owner')['items'] if x['kind']=='gift']
        self.assertEqual(len(items),16)
        from .seed_gifts import ROOM_GIFTS,NAMESPACE
        original=next(x for x in items if x['id']==str(uuid.uuid5(NAMESPACE,'original-room:rose')))
        self.assertEqual(original['price'],5)
        for name,title,price in ROOM_GIFTS:
            row=next(x for x in items if x['id']==str(uuid.uuid5(NAMESPACE,'original-room:'+name)))
            self.assertEqual((row['title'],row['price']),(title,price))
        with self.control.db() as db:
            db.execute('UPDATE account_catalog SET price=42,active=0 WHERE id=?',(original['id'],))
        with self.control.db() as db:
            db.execute('UPDATE account_catalog SET price=123,active=0 WHERE id=?',(items[0]['id'],))
            frames=db.execute('SELECT frames FROM account_media WHERE id=?',(items[0]['media_id'],)).fetchone()[0]
        self.assertGreater(frames,1)
        self.assertEqual(seed(self.path)['added'],0)
        with self.control.db() as db:
            self.assertEqual(tuple(db.execute('SELECT price,active FROM account_catalog WHERE id=?',(original['id'],)).fetchone()),(42,0))
        with self.control.db() as db:
            self.assertEqual(tuple(db.execute('SELECT price,active FROM account_catalog WHERE id=?',(items[0]['id'],)).fetchone()),(123,0))

    def test_grants_fit_equipment_hide_and_revoke(self):
        self.setup_catalog();item=self.item(price=50)
        with self.assertRaises(HTTPException):self.catalog.select('alice',SelectInput(kind='frame',item_id=item['id']))
        self.catalog.grant('owner',GrantInput(target_uid='alice',item_id=item['id']))
        self.assertEqual(self.profiles.get('alice')['equipped']['frame']['avatar_scale'],.46)
        self.assertIn(item['id'],self.catalog.listing('alice')['owned'])
        self.catalog.grant('owner',GrantInput(target_uid='alice',item_id=item['id'],revoke=True))
        self.assertEqual(self.profiles.get('alice')['equipped'],{})
        self.catalog.save('owner',ItemInput(**{k:v for k,v in item.items() if k not in ('url','updated_at')},))
        with self.assertRaises(HTTPException):self.catalog.grant('support',GrantInput(target_uid='alice',item_id=item['id']))
    def test_purchase_retry_price_check_and_atomic_concurrent_balance(self):
        self.setup_catalog();one=self.item(price=7);two=self.item(price=7)
        bad=BuyInput(item_id=one['id'],request_id=uuid.uuid4(),expected_price=6)
        with self.assertRaises(HTTPException):self.catalog.transact('alice',bad)
        requests=[BuyInput(item_id=x['id'],request_id=uuid.uuid4(),expected_price=7) for x in (one,two)]
        def buy(data):
            try:return self.catalog.transact('alice',data)
            except HTTPException as e:return e.status_code
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(buy,requests))
        self.assertEqual(sum(isinstance(r,dict) for r in results),1)
        winning=requests[next(i for i,r in enumerate(results) if isinstance(r,dict))]
        self.assertEqual(self.catalog.transact('alice',winning)['coins_spent'],7)
        with self.control.db() as db:self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='alice'").fetchone()[0],3)
    def test_paid_gift_multiple_targets_self_gift_and_retry(self):
        self.setup_catalog();room=self.seed_owner();gift=self.item('gift',30)
        data=GiftInput(item_id=gift['id'],expected_price=30,request_id=uuid.uuid4(),recipient_uids=['owner','alice','alice'])
        result=self.catalog.transact('owner',data,room)
        self.assertEqual(result['coins_spent'],60)
        self.assertEqual(self.catalog.transact('owner',data,room),result)
        with self.control.db() as db:
            self.assertEqual(db.execute("SELECT SUM(coin_delta),SUM(diamond_delta) FROM account_wallet_ledger WHERE firebase_uid='owner'").fetchone()[:],(40,30))
            self.assertEqual(db.execute("SELECT SUM(diamond_delta) FROM account_wallet_ledger WHERE firebase_uid='alice'").fetchone()[0],35)
        events=self.catalog.events('owner',room)
        self.assertEqual(len(events['items']),2)
        self.assertEqual(events['items'][0]['asset']['url'],gift['url'])
        from .broadcasts import Broadcasts
        announcements=Broadcasts(self.path).read()['items']
        self.assertEqual(len(announcements),2)
        self.assertTrue(all(e['kind']=='gift' for e in announcements))
        self.assertEqual(announcements[0]['gift']['count'],1)
        self.assertEqual(announcements[0]['gift']['url'],gift['url'])
    def test_unverified_recipient_rolls_back_gift_and_entry_heartbeat_is_not_replayed(self):
        self.setup_catalog();room=self.seed_owner();gift=self.item('gift',30)
        with self.assertRaises(HTTPException):self.catalog.transact('owner',GiftInput(item_id=gift['id'],expected_price=30,request_id=uuid.uuid4(),recipient_uids=['support']),room)
        with self.control.db() as db:self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='owner'").fetchone()[0],100)
        entry=self.item('entry');self.catalog.grant('owner',GrantInput(target_uid='alice',item_id=entry['id']))
        rooms=Rooms(self.path);rooms.presence('alice',room,leave=True);rooms.presence('alice',room);rooms.presence('alice',room)
        self.assertEqual(len(self.catalog.events('alice',room)['items']),1)
        details=self.catalog.details('owner','alice');self.assertTrue(details['online']);self.assertEqual(details['presence']['room_id'],room)

    def test_bundled_import_preserves_admin_edits_grants_and_paid_lock(self):
        import json
        import tempfile
        from pathlib import Path
        from .seed_bundled_catalog import seed,item_id
        self.setup_catalog()
        rows=json.loads(Path(__file__).with_name('bundled_catalog.json').read_text())
        with tempfile.TemporaryDirectory() as folder:
            for item in rows:
                path=Path(folder)/item['path'];path.parent.mkdir(parents=True,exist_ok=True)
                image=io.BytesIO();Image.new('RGBA',(32,32),(255,0,0,0)).save(image,format='PNG')
                path.write_bytes(image.getvalue())
            result=seed(self.path,folder)
            self.assertEqual(result['added'],len(rows))
            key=item_id(rows[0])
            with self.catalog.control.db() as db:
                db.execute("UPDATE account_catalog SET title='Owner edited',price=99,active=0 WHERE id=?",(key,))
            entry=next(item_id(r) for r in rows if r['kind']=='entry')
            with self.assertRaises(HTTPException):
                self.catalog.select('alice',SelectInput(kind='entry',item_id=entry))
            self.catalog.grant('owner',GrantInput(target_uid='alice',item_id=entry))
            self.assertEqual(seed(self.path,folder)['added'],0)
            saved=next(r for r in self.catalog.listing('owner',True)['items'] if r['id']==key)
            self.assertEqual((saved['title'],saved['price'],saved['active']),('Owner edited',99,False))
            self.assertIn(entry,self.catalog.listing('alice')['owned'])
            banner=next(r for r in self.catalog.listing('owner',True)['items'] if r['kind']=='banner')
            self.assertIn('builtin_slide',banner)
            other=io.BytesIO();Image.new('RGB',(32,32),'blue').save(other,format='PNG')
            replacement=self.catalog.upload('owner',other.getvalue())
            with self.catalog.control.db() as db:
                db.execute('UPDATE account_catalog SET media_id=? WHERE id=?',(replacement['id'],banner['id']))
            edited=next(r for r in self.catalog.listing('owner',True)['items'] if r['id']==banner['id'])
            self.assertNotIn('builtin_slide',edited)

    def test_actual_bundled_media_meets_upload_limits(self):
        import json
        from pathlib import Path
        rows=json.loads(Path(__file__).with_name('bundled_catalog.json').read_text())
        if not Path('assets/effects').is_dir():self.skipTest('Bundled artwork is checked in repository CI')
        self.setup_catalog()
        for item in rows:
            with self.subTest(path=item['path']):
                self.catalog.upload('owner',Path(item['path']).read_bytes())

    def test_gift_quantity_is_atomic_and_retries_do_not_spend_twice(self):
        self.setup_catalog();room=self.seed_owner();gift=self.item('gift',2)
        data=GiftInput(item_id=gift['id'],recipient_uids=['alice'],quantity=10,expected_price=2,request_id=uuid.uuid4())
        first=self.catalog.transact('owner',data,room)
        self.assertEqual(first['coins_spent'],20);self.assertEqual(first['diamond_each'],20)
        self.assertEqual(first,self.catalog.transact('owner',data,room))
        with self.assertRaises(HTTPException):self.catalog.transact('owner',data.model_copy(update={'quantity':5}),room)
        with self.control.db() as db:
            self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='owner'").fetchone()[0],80)
            self.assertEqual(db.execute("SELECT price FROM account_gift_receipts WHERE sender='owner'").fetchone()[0],20)

if __name__=='__main__':unittest.main()
