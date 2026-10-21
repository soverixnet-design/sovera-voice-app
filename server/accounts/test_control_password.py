import sqlite3
import unittest
from fastapi import HTTPException
from . import test_control
from .control_password import Passwords

class PasswordTests(unittest.TestCase):
    setUp=test_control.ControlTests.setUp
    def setup_password(self):
        self.passwords=Passwords(self.control)
        self.passwords.set('owner','Soverix','correct-password-2026')
    def test_direct_login_cookie_origin_and_logout(self):
        self.setup_password()
        url='/sovera/control/password-login'
        body={'username':'SOVERIX','password':'correct-password-2026'}
        self.assertEqual(self.client.post(url,json=body).status_code,403)
        response=self.client.post(url,json=body,headers={'Origin':'https://admin.soverixnet.com'})
        self.assertEqual(response.status_code,200,response.text)
        for flag in ('Secure','HttpOnly','SameSite=strict','Path=/'):self.assertIn(flag,response.headers['set-cookie'])
        self.assertEqual(self.client.get('/sovera/control/session').json()['role'],'owner')
        self.client.post('/sovera/control/logout',headers={'Origin':'https://admin.soverixnet.com'})
        self.assertEqual(self.client.get('/sovera/control/session').status_code,401)
    def test_hash_at_rest_reset_revokes_and_no_public_signup(self):
        self.setup_password()
        token=self.passwords.login('soverix','correct-password-2026')
        with self.control.db() as db:
            row=db.execute('SELECT * FROM account_control_passwords').fetchone()
            self.assertNotIn('correct-password',str(dict(row)))
        self.passwords.set('owner','soverix','replacement-password')
        with self.assertRaises(HTTPException):self.control.actor(token)
        with self.assertRaises(HTTPException):self.passwords.login('soverix','correct-password-2026')
        self.assertEqual(self.control.actor(self.passwords.login('soverix','replacement-password')),'owner')
        with self.assertRaises(HTTPException):self.passwords.set('alice','alice','long-enough-password')
        with self.assertRaises(ValueError):self.passwords.set('owner','soverix','short')
    def test_rate_limit_persists_across_service_restarts(self):
        self.setup_password()
        for _ in range(8):
            with self.assertRaises(HTTPException) as error:Passwords(self.control).login('soverix','bad')
            self.assertEqual(error.exception.status_code,401)
        with self.assertRaises(HTTPException) as error:self.passwords.login('soverix','correct-password-2026')
        self.assertEqual(error.exception.status_code,429)
        with self.control.db() as db:db.execute('UPDATE account_control_login_attempts SET created_at=0')
        self.assertEqual(self.control.actor(self.passwords.login('soverix','correct-password-2026')),'owner')
    def test_unknown_login_and_revoked_staff(self):
        self.setup_password()
        for name in ('missing','bad name'):
            with self.assertRaises(HTTPException) as error:self.passwords.login(name,'bad')
            self.assertEqual(error.exception.status_code,401)
        token=self.passwords.login('soverix','correct-password-2026')
        with self.control.db() as db:db.execute("DELETE FROM account_staff WHERE uid='owner'")
        with self.assertRaises(HTTPException):self.passwords.login('soverix','correct-password-2026')
        with self.assertRaises(HTTPException):self.control.actor(token)

if __name__=='__main__':unittest.main()
