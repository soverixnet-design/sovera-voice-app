import unittest
from types import SimpleNamespace
from unittest.mock import Mock
from fastapi import HTTPException
from server.food.identity import FirebaseIdentity
from server.food import runtime

class IdentityTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.auth=Mock()
        self.auth.verify_id_token.return_value={'uid':'real-user'}
        self.auth.get_user.return_value=SimpleNamespace(disabled=False,custom_claims={})
        self.db=Mock();self.doc=self.db.collection.return_value.document.return_value.get.return_value
        self.doc.exists=True;self.doc.to_dict.return_value={'is_banned':False,'role':'owner'}
        self.identity=FirebaseIdentity(self.auth,self.db,'fixed-project-app')
    async def test_verified_token_checks_revocation(self):
        self.assertEqual(await self.identity.verify('id-token'),'real-user')
        self.auth.verify_id_token.assert_called_once_with('id-token',app='fixed-project-app',check_revoked=True)
    async def test_bad_and_revoked_tokens_fail_closed(self):
        self.auth.verify_id_token.side_effect=ValueError('sensitive SDK body')
        with self.assertRaises(HTTPException) as result:await self.identity.verify('bad')
        self.assertEqual(result.exception.detail,'Invalid session')
    async def test_profile_role_cannot_grant_owner(self):
        self.assertFalse(await self.identity.owner('real-user'))
        self.auth.get_user.return_value.custom_claims={'sovera_owner':True}
        self.assertTrue(await self.identity.owner('real-user'))
    async def test_disabled_banned_missing_and_unavailable_denied(self):
        self.auth.get_user.return_value.disabled=True
        self.assertFalse(self.identity.eligible('u'))
        self.auth.get_user.return_value.disabled=False
        self.doc.to_dict.return_value={'is_banned':True}
        self.assertFalse(self.identity.eligible('u'))
        self.doc.to_dict.return_value={}
        self.assertFalse(self.identity.eligible('u'))
        self.doc.exists=False
        self.assertFalse(self.identity.eligible('u'))
        self.db.collection.return_value.document.return_value.get.side_effect=Exception('unavailable')
        self.assertFalse(self.identity.eligible('u'))
    async def test_runtime_cannot_create_second_wallet(self):
        from unittest.mock import patch
        with patch.dict('os.environ',{},clear=True):
            with self.assertRaisesRegex(RuntimeError,'wallet migration'):
                runtime.create()

if __name__=='__main__':unittest.main()
