"""Bounded Firebase-to-Greedy game access tokens.

The uploaded Node Greedy server accepts HS256 JWT. Only this Firebase-authenticated
account server may mint them. Never use the user's Firebase ID token directly in
a WebSocket URL. No wallet access, betting or coins are enabled by this module.

Until the REAL Sovera wallet's transactional debit/credit endpoints and Node
server are deployed and verified, fail closed rather than serving demo bots.
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from urllib.parse import urlparse
from fastapi import HTTPException

def _encode(value):
    raw=json.dumps(value,separators=(',',':'),ensure_ascii=False).encode('utf-8')
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode('ascii')

def greedy_access(uid,profile,*,now=None):
    # This deliberate two-factor rollout gate prevents accidental activation
    # of paid coins / standalone mock wallet in existing accounts.
    if os.getenv('SOVERA_GREEDY_ENABLED')!='1':
        raise HTTPException(503,'Greedy game is not active yet')
    secret=os.getenv('SOVERA_GREEDY_JWT_SECRET','')
    game_url=os.getenv('SOVERA_GREEDY_PUBLIC_URL','')
    wallet_verified=os.getenv('SOVERA_GREEDY_WALLET_VERIFIED')=='1'
    url=urlparse(game_url)
    if len(secret)<32 or not wallet_verified or url.scheme!='https' or not url.hostname or url.username or url.password or url.query or url.fragment or not game_url.endswith('/'):
        raise HTTPException(503,'Greedy wallet and game service are not yet configured')
    if not isinstance(uid,str) or not uid or len(uid)>128:
        raise HTTPException(401,'Invalid session')
    ts=int(time.time() if now is None else now)
    payload={'uid':uid,'name':str(profile['display_name'])[:40],
             'avatar':str(profile['avatar_url'] or '')[:500],
             'iat':ts,'nbf':ts-3,'exp':ts+300,'jti':secrets.token_hex(12)}
    head=_encode({'alg':'HS256','typ':'JWT'})
    body=_encode(payload)
    signed=f'{head}.{body}'
    digest=hmac.new(secret.encode('utf-8'),signed.encode('ascii'),hashlib.sha256).digest()
    signature=base64.urlsafe_b64encode(digest).rstrip(b'=').decode('ascii')
    return {'game_url':game_url,'token':signed+'.'+signature,
            'expires_at':ts+300,'paid_game':True}
