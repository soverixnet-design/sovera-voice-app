import time
import uuid
import unittest
from unittest.mock import patch
from fastapi import HTTPException
from . import test_control
from .control import Control
from .control_password import Passwords
from .control_security import Security,FactorInput,totp
from .operations import Operations,RoomModeration,PolicyInput,TicketInput,csv_content
from .rooms import Rooms,RoomInput
from .community import Community,CommunityText
from .programs import Programs,Pack,Buy,ReferralPolicy,PaymentOrder,PaymentDecision,AgencyFinance,AgencyTerms,month_bounds

class OperationsTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    login=test_control.ControlTests.login
    def test_mfa_password_code_replay_recovery_and_session_revocation(self):
        passwords=Passwords(self.control);passwords.set('owner','owner','correct-password-123')
        sec=Security(self.path);data=sec.enroll('owner',FactorInput(password='correct-password-123'))
        counter=int(time.time())//30;result=sec.confirm('owner',totp(data['secret'],counter),'unused')
        self.assertEqual(len(result['recovery_codes']),10)
        with self.assertRaises(HTTPException):passwords.login('owner','correct-password-123')
        token=passwords.login('owner','correct-password-123',result['recovery_codes'][0]);self.assertEqual(self.control.actor(token),'owner')
        with self.assertRaises(HTTPException):passwords.login('owner','correct-password-123',result['recovery_codes'][0])
        code=self.control.code('owner')['code']
        with self.assertRaises(HTTPException):self.control.login(code)
        token2=self.control.login(code,result['recovery_codes'][1]);state=sec.state('owner',token2)
        self.assertEqual(state['recovery_remaining'],8);self.assertEqual(len(state['sessions']),2)
        sec.revoke('owner',next(s['id'] for s in state['sessions'] if not s['current']))
        with self.assertRaises(HTTPException):self.control.actor(token)
    def test_room_close_enforced_and_report_is_owner_only(self):
        rooms=Rooms(self.path);room=rooms.save('owner',RoomInput(name='A room'))['id'];rooms.presence('alice',room)
        ops=Operations(self.path)
        with self.assertRaises(HTTPException):ops.moderate('agent',room,RoomModeration(status='closed',reason='review'))
        ops.moderate('owner',room,RoomModeration(status='closed',reason='review'))
        with self.assertRaises(HTTPException):rooms.presence('alice',room)
        self.assertEqual(rooms.directory(),[])
        ops.moderate('owner',room,RoomModeration(status='open',reason='resolved'));self.assertEqual(len(rooms.directory()),1)
        self.assertIn('daily',ops.overview('owner'))
        with self.assertRaises(HTTPException):ops.overview('agent')
    def test_ticket_routing_staff_policy_csv_and_observed_activity(self):
        c=Community(self.path);ticket=c.write('alice','support',CommunityText(text='Need help',request_id=uuid.uuid4()))['id'];ops=Operations(self.path)
        ops.ticket('support',ticket,TicketInput(status='in_progress',assignee='support',note='Investigating'))
        self.assertEqual(ops.tickets('support','in_progress')[0]['id'],ticket)
        self.assertIn("'=SUM",csv_content([{'name':'=SUM(A1)','coins':12}]))
        self.client.get('/sovera/account',headers={'Authorization':'Bearer alice','User-Agent':'Test phone'})
        self.assertTrue(ops.records('owner','access',target='alice'))
        ops.policy('owner','agent',PolicyInput(expires_at=1))
        with self.assertRaises(HTTPException):self.control.actor(self.control.login(self.control.code('agent')['code']))

class ProgramTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    def test_membership_uses_real_coins_once_and_expiry_is_visible(self):
        p=Programs(self.path);pack=Pack(id=uuid.uuid4(),kind='vip',title='VIP One',coins=5,days=7);p.save_pack('owner',pack)
        buy=Buy(item_id=pack.id,request_id=uuid.uuid4(),expected_coins=5)
        first=p.buy('alice',buy);self.assertEqual(first,p.buy('alice',buy));self.assertEqual(first['coins'],'5')
        self.assertEqual(p.catalog('alice')['membership']['level'],1)
        with patch('server.accounts.programs.time.time',return_value=first['expires_at']+1):self.assertIsNone(p.catalog('alice')['membership'])
        with self.assertRaises(HTTPException):p.save_pack('agent',pack)
    def test_manual_payment_never_credits_before_approval_and_refund_is_once(self):
        p=Programs(self.path);pack=Pack(id=uuid.uuid4(),kind='recharge',title='Verified top up',coins=100,instructions='Owner verifies provider receipt');p.save_pack('owner',pack)
        req=PaymentOrder(item_id=pack.id,request_id=uuid.uuid4(),reference='REAL-RECEIPT-1');p.payment('alice',req)
        with self.control.db() as db:self.assertEqual(db.execute('SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid=\'alice\'').fetchone()[0],10)
        decision=PaymentDecision(action='approve',note='Confirmed in merchant statement');p.decide('owner',str(req.request_id),decision);self.assertTrue(p.decide('owner',str(req.request_id),decision)['duplicate'])
        self.assertEqual(p.payments('alice')[0]['status'],'approved')
        p.decide('owner',str(req.request_id),PaymentDecision(action='refund',note='Cash refund separately recorded'))
        with self.control.db() as db:self.assertEqual(db.execute('SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid=\'alice\'').fetchone()[0],10)
    def test_referral_requires_verified_recharge_not_signup_or_adjustment(self):
        p=Programs(self.path);p.policy('owner',ReferralPolicy(enabled=True,reward_coins=7,recharge_target=20))
        with self.control.db() as db:
            db.execute("INSERT INTO account_wallet_links VALUES('agent','agent-wallet',1,'active')")
            code=db.execute("SELECT public_id FROM account_public_ids WHERE uid='agent'").fetchone()[0]
        p.refer('alice',code)
        with self.assertRaises(HTTPException):p.referral_claim('agent','alice')
        from .control import RechargeInput
        self.control.recharge('owner',RechargeInput(target_uid='alice',amount=20,note='verified',request_id=uuid.uuid4()))
        p.referral_claim('agent','alice');self.assertTrue(p.referral_claim('agent','alice')['duplicate'])
    def test_future_agency_terms_are_immutable_and_not_paid_early(self):
        from .members import Members,AgencyInput
        agency=uuid.uuid4();Members(self.path).agency_save('owner',AgencyInput(id=agency,name='Hosts',manager='agent'))
        f=AgencyFinance(self.path);now=int(time.time());month='2027-01';terms=AgencyTerms(id=uuid.uuid4(),agency=agency,month=month,target=100,salary=20,rate=3)
        with patch('server.accounts.programs.time.time',return_value=month_bounds(month)[0]-86400):f.save_terms('owner',terms)
        self.assertEqual(f.income('agent')['items'][0]['commission'],0)
        with self.assertRaises(HTTPException):f.pay('owner',str(terms.id))

class MaintenanceTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    def test_backup_checks_copy_hash_and_retains_live_wallet(self):
        import tempfile
        from pathlib import Path
        from .maintenance import backup,file_hash,record_backup
        with tempfile.TemporaryDirectory() as directory:
            result=backup(directory,{'account':self.path})
            self.assertTrue(result['verified']);record_backup(self.path,result)
            self.assertTrue(Operations(self.path).maintenance_status('owner')['backups'][0]['verified'])
            copy=next(Path(directory).glob('*/account.sqlite3'))
            self.assertEqual(file_hash(copy),result['files']['account']['sha256'])
            self.assertGreater(result['files']['account']['counts']['account_profiles'],0)
        self.assertEqual(self.control.users('owner','alice')[0]['coins'],10)
    def test_cancelled_intent_cannot_later_debit_or_create_order(self):
        p=Programs(self.path);pack=Pack(id=uuid.uuid4(),kind='vip',title='VIP cancel',coins=5);p.save_pack('owner',pack)
        key=uuid.uuid4();self.assertFalse(p.cancel_request('alice',str(key))['applied'])
        with self.assertRaises(HTTPException):p.buy('alice',Buy(item_id=pack.id,request_id=key,expected_coins=5))
        self.assertEqual(self.control.users('owner','alice')[0]['coins'],10)
    def test_filtered_members_and_maintenance_routes_require_owner(self):
        ops=Operations(self.path)
        self.assertEqual([r['uid'] for r in ops.members('owner',q='alice',minimum=10)],['alice'])
        self.assertEqual(ops.members('owner',q='alice',minimum=11),[])
        # Direct service and worker share the same schema without altering balances.
        from .maintenance import tick
        tick(self.path)
        state=ops.maintenance_status('owner');self.assertEqual(state['jobs'][0]['ok'],1)
        with self.assertRaises(HTTPException):ops.members('support')
    def test_native_staff_routes_obey_restrictions(self):
        c=Community(self.path);ops=Operations(self.path)
        ops.policy('owner','support',PolicyInput(expires_at=0,denied=['support']))
        with self.assertRaises(HTTPException):c.require_staff('support')
