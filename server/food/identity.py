"""Firebase Admin identity adapter. Server credentials never enter the app."""
import asyncio
from fastapi import HTTPException

class FirebaseIdentity:
    def __init__(self, auth, firestore, firebase_app):
        self.auth, self.firestore, self.firebase_app = auth, firestore, firebase_app

    def eligible(self, uid):
        try:
            account = self.auth.get_user(uid, app=self.firebase_app)
            profile = self.firestore.collection('sovera_profiles').document(uid).get()
            return (not account.disabled and profile.exists
                    and profile.to_dict().get('is_banned') is False)
        except Exception:
            return False

    async def verify(self, token):
        if not isinstance(token, str) or not 1 <= len(token) <= 16000:
            raise HTTPException(401, 'Invalid session')
        try:
            claims = await asyncio.to_thread(self.auth.verify_id_token, token,
                app=self.firebase_app, check_revoked=True)
            uid = claims.get('uid')
            if not isinstance(uid,str) or not uid or len(uid)>128:
                raise ValueError('Missing UID')
        except Exception:
            raise HTTPException(401, 'Invalid session') from None
        if not await asyncio.to_thread(self.eligible, uid):
            raise HTTPException(403, 'Account unavailable')
        return uid

    async def owner(self, uid):
        if not await asyncio.to_thread(self.eligible, uid):
            return False
        try:
            account = await asyncio.to_thread(self.auth.get_user, uid, app=self.firebase_app)
            # Custom claims are set only by a trusted Firebase Admin principal.
            # Never accept an editable profile role or client-provided flag.
            return (account.custom_claims or {}).get('sovera_owner') is True
        except Exception:
            return False
