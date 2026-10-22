import sqlite3
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from fastapi.testclient import TestClient
from fastapi import HTTPException
from server.accounts.app import Profiles,create_app
from server.accounts.control import Control,RechargeInput,StaffInput

class ControlTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory();self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/'profiles.db'
        self.profiles=Profiles(self.path)
        async def verify(token):
            if token not in ('owner','agent','alice','support'):raise ValueError()
            return token
        self.app=create_app(self.profiles,verify)
        self.client=TestClient(self.app,base_url='https://admin.soverixnet.com')
        self.control=Control(self.path)
        for uid in ('owner','agent','alice','support'):
            self.client.put('/sovera/account',headers={'Authorization':'Bearer '+uid},json={'display_name':uid,'country':'BD','bio':''})
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_staff VALUES('owner','owner')")
            db.execute("INSERT INTO account_staff VALUES('support','support')")
            db.execute("INSERT INTO account_control_agents VALUES('agent',100,0)")
            db.execute("INSERT INTO account_wallet_links VALUES('alice','legacy-alice',1,'active')")
            db.execute("INSERT INTO account_wallet_ledger VALUES('import-alice','alice',10,5,'verified_import',1)")
    def login(self,uid='owner'):
        code=self.client.post('/sovera/account/staff/access-code',headers={'Authorization':'Bearer '+uid}).json()['code']
        response=self.client.post('/sovera/control/login',json={'code':code},headers={'Origin':'https://admin.soverixnet.com'})
        self.assertEqual(response.status_code,200)
        return code,response
    def recharge(self,**extra):return RechargeInput(target_uid='alice',amount=70,request_id=uuid.uuid4(),**extra)

    def test_exchange_rate_owner_only_and_retry_preserves_paid_amount(self):
        self.login()
        origin={'Origin':'https://admin.soverixnet.com'}
        self.assertEqual(self.client.put('/sovera/control/exchange-policy',json={'coins_per_100':40},headers=origin).status_code,200)
        with sqlite3.connect(self.path) as db:
            db.execute("INSERT INTO account_wallet_ledger VALUES('test-diamonds','alice',0,1000,'verified_import',1)")
        payload={'diamonds':100,'request_id':str(uuid.uuid4())}
        auth={'Authorization':'Bearer alice'}
        first=self.client.post('/sovera/account/wallet/exchange',headers=auth,json=payload)
        self.assertEqual(first.json()['coins_received'],'40')
        self.client.put('/sovera/control/exchange-policy',json={'coins_per_100':30},headers=origin)
        self.assertEqual(self.client.post('/sovera/account/wallet/exchange',headers=auth,json=payload).json()['coins_received'],'40')
        self.login('support')
        self.assertEqual(self.client.put('/sovera/control/exchange-policy',json={'coins_per_100':99},headers=origin).status_code,403)

    def test_owner_large_recharge_keeps_exact_balance_and_retry(self):
        data=RechargeInput(target_uid='alice',amount=2000000000000,request_id=uuid.uuid4())
        result=self.control.recharge('owner',data)
        self.assertEqual(result['balance'],2000000000010)
        self.assertEqual(self.control.recharge('owner',data)['balance'],result['balance'])

    def test_native_identity_cannot_assign_staff_or_mint_owner_access(self):
        response=self.client.post('/sovera/account/staff/access-code',headers={'Authorization':'Bearer alice'})
        self.assertEqual(response.status_code,403)
        self.assertEqual(self.client.get('/sovera/control/session').status_code,401)
        self.assertEqual(self.client.get('/sovera/account/staff',headers={'Authorization':'Bearer alice'}).json()['role'],None)

    def test_single_use_codes_cookie_security_logout_and_origin(self):
        code,response=self.login()
        cookie=response.headers['set-cookie']
        for flag in ('Secure','HttpOnly','SameSite=strict','Path=/'):self.assertIn(flag,cookie)
        self.assertEqual(self.client.get('/sovera/control/session').json()['role'],'owner')
        self.assertEqual(self.client.post('/sovera/control/login',json={'code':code},headers={'Origin':'https://admin.soverixnet.com'}).status_code,401)
        self.assertEqual(self.client.post('/sovera/control/logout',json={},headers={'Origin':'https://evil.example'}).status_code,403)
        self.assertEqual(self.client.post('/sovera/control/logout',json={},headers={'Origin':'https://admin.soverixnet.com'}).status_code,200)
        self.assertEqual(self.client.get('/sovera/control/session').status_code,401)
        other=TestClient(self.app)
        self.assertEqual(other.get('/sovera/control/session').status_code,403)

    def test_expired_code_and_role_revocation_reject_existing_sessions(self):
        code=self.control.code('owner')['code']
        with sqlite3.connect(self.path) as db:db.execute('UPDATE account_control_codes SET expires=1')
        with self.assertRaises(HTTPException):self.control.login(code)
        self.login('agent')
        with sqlite3.connect(self.path) as db:db.execute("DELETE FROM account_control_agents WHERE uid='agent'")
        self.assertEqual(self.client.get('/sovera/control/session').status_code,403)

    def test_recharge_idempotency_verified_ledger_and_receipt_survive_restart(self):
        data=self.recharge()
        first=self.control.recharge('agent',data)
        again=Control(self.path).recharge('agent',data)
        self.assertEqual(first,again)
        self.assertEqual(first['balance'],80)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("SELECT used FROM account_control_agents WHERE uid='agent'").fetchone()[0],70)
            self.assertEqual(db.execute("SELECT SUM(coin_delta) FROM account_wallet_ledger WHERE firebase_uid='alice'").fetchone()[0],80)
        with self.assertRaises(HTTPException):self.control.recharge('agent',data.model_copy(update={'amount':71}))

    def test_concurrent_quota_and_role_boundaries(self):
        def run(_):
            try:return self.control.recharge('agent',self.recharge())
            except HTTPException as e:return e.status_code
        with ThreadPoolExecutor(max_workers=2) as pool:result=list(pool.map(run,range(2)))
        self.assertEqual(sum(isinstance(r,dict) for r in result),1)
        with self.assertRaises(HTTPException):self.control.recharge('support',self.recharge())
        with self.assertRaises(HTTPException):self.control.staff('agent')
        with self.assertRaises(HTTPException):self.control.recharge('owner',self.recharge().model_copy(update={'target_uid':'owner'}))

    def test_staff_quota_cannot_be_reset_by_revocation_and_regrant(self):
        self.control.recharge('agent',self.recharge())
        self.control.staff('owner',StaffInput(target_uid='agent',role='none',quota=0))
        with self.assertRaises(HTTPException):self.control.staff('owner',StaffInput(target_uid='agent',role='agent',quota=1))
        self.control.staff('owner',StaffInput(target_uid='agent',role='agent',quota=100))
        with sqlite3.connect(self.path) as db:self.assertEqual(db.execute("SELECT used FROM account_control_agents WHERE uid='agent'").fetchone()[0],70)
        with self.assertRaises(HTTPException):self.control.staff('owner',StaffInput(target_uid='owner',role='none',quota=0))

    def test_support_cannot_recharge_or_publish(self):
        self.login('support')
        payload={'target_uid':'alice','amount':5,'request_id':str(uuid.uuid4())}
        headers={'Origin':'https://admin.soverixnet.com'}
        self.assertEqual(self.client.post('/sovera/control/recharge',headers=headers,json=payload).status_code,403)
        self.assertEqual(self.client.post('/sovera/control/publications',headers=headers,json={'title':'No','text':'No','section':'notices','request_id':str(uuid.uuid4())}).status_code,403)
        self.assertEqual(self.client.get('/sovera/control/support').status_code,200)

if __name__=='__main__':unittest.main()
