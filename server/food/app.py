"""API factory: deployment must supply verified identity and owner checks."""
import asyncio
import contextlib
from contextlib import asynccontextmanager
from typing import Literal
from fastapi import FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, StrictInt, ConfigDict
from .engine import Rejected

class Bet(BaseModel):
    model_config = ConfigDict(extra='forbid')
    round: StrictInt
    slot: Literal['chk','fish','hot','stk','grp','let','pep','mel']
    amount: StrictInt

class Auto(BaseModel):
    model_config = ConfigDict(extra='forbid')
    slot: Literal['chk','fish','hot','stk','grp','let','pep','mel']
    amount: StrictInt
    rounds: StrictInt


def create_app(engine, verify_identity, require_owner):
    """verify_identity(token)->uid; require_owner(uid)->True, both async.

    Identity adapter must check issuer/audience/expiry, disabled/banned users.
    Owner adapter must read server permissions, not token/client role fields.
    Intentionally no permissive fallback, no public balance-credit API.
    """
    async def identify(authorization):
        if not authorization or not authorization.startswith('Bearer '):
            raise HTTPException(401,'Sign in required')
        uid = await verify_identity(authorization[7:])
        if not isinstance(uid,str) or not uid or len(uid)>128:
            raise HTTPException(401,'Invalid identity')
        return uid

    async def scheduler():
        while True:
            await asyncio.to_thread(engine.state,'__scheduler__')
            await asyncio.sleep(.25)

    @asynccontextmanager
    async def lifespan(app):
        task=asyncio.create_task(scheduler())
        try:
            yield
        finally:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    app=FastAPI(lifespan=lifespan,docs_url=None,redoc_url=None)

    @app.exception_handler(Rejected)
    async def rejected(request,error):
        from fastapi.responses import JSONResponse
        return JSONResponse({'detail':str(error)},status_code=409,headers={'Cache-Control':'no-store'})

    @app.middleware('http')
    async def no_cache(request,call_next):
        response=await call_next(request)
        response.headers['Cache-Control']='no-store'
        return response

    @app.get('/food/state')
    async def state(authorization: str=Header(default='')):
        uid=await identify(authorization)
        return await asyncio.to_thread(engine.state,uid)

    @app.post('/food/bet')
    async def bet(body:Bet,authorization: str=Header(default=''),idempotency_key: str=Header(default='')):
        uid=await identify(authorization)
        return await asyncio.to_thread(engine.bet,uid,body.round,body.slot,body.amount,idempotency_key)

    @app.post('/food/auto')
    async def auto(body:Auto,authorization: str=Header(default='')):
        uid=await identify(authorization)
        return await asyncio.to_thread(engine.autoplay,uid,body.slot,body.amount,body.rounds)

    @app.get('/food/history')
    async def history(authorization: str=Header(default='')):
        uid=await identify(authorization)
        return (await asyncio.to_thread(engine.state,uid))['history']

    @app.put('/food/admin/config')
    async def config(body:dict[str,StrictInt],authorization: str=Header(default='')):
        uid=await identify(authorization)
        if await require_owner(uid) is not True:
            raise HTTPException(403,'Owner permission required')
        return await asyncio.to_thread(engine.configure,body)

    @app.websocket('/food/events')
    async def events(ws:WebSocket):
        # Same-origin deployment; no bearer secrets in URL or access logs.
        origin=ws.headers.get('origin')
        if origin and origin.removeprefix('https://').removeprefix('http://') != ws.headers.get('host'):
            await ws.close(code=1008); return
        await ws.accept()
        try:
            msg=await asyncio.wait_for(ws.receive_json(),10)
            authorization=msg.get('authorization','')
            seen_start=seen_result=None
            while True:
                # Revalidate so expired/revoked sessions cannot keep receiving.
                uid=await identify(authorization)
                s=await asyncio.to_thread(engine.state,uid)
                await ws.send_json({'event':'state','data':s})
                if s['phase']=='bet' and seen_start!=s['round']:
                    await ws.send_json({'event':'round_start','data':{'round':s['round'],'endsAt':s['endsAt'],'serverNow':s['serverNow']}})
                    seen_start=s['round']
                if s['slot'] is not None and seen_result!=s['round']:
                    await ws.send_json({'event':'round_result','data':{k:s[k] for k in ('round','slot','myWin','myBet','top3')}})
                    # Names/avatars stay null until a trusted public-profile adapter exists.
                    if s['top3']:
                        await ws.send_json({'event':'big_win','data':{**s['top3'][0],'amount':s['top3'][0]['win'],'round':s['round']}})
                    seen_result=s['round']
                await asyncio.sleep(1)
        except (WebSocketDisconnect,HTTPException,asyncio.TimeoutError,ValueError,AttributeError):
            with contextlib.suppress(RuntimeError):
                await ws.close(code=1008)
    return app
