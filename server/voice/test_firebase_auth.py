"""Fail-closed contract tests; no external requests or real credentials."""
import asyncio
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import uuid
import httpx
os.environ.setdefault('SOVERA_AUTH_URL', 'https://example.invalid')
os.environ.setdefault('SOVERA_PUBLIC_KEY', 'fixture')
spec = importlib.util.spec_from_file_location('gateway_firebase_test', Path(__file__).with_name('app.py'))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
REAL_CLIENT = httpx.AsyncClient

class FirebaseAuthorization(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        g.FIREBASE_PROJECT = 'fixture-project'
        g.FIREBASE_KEY = 'fixture-public-key'
        self.requests = []
        self.identity_status = 200
        self.identity = {'users': [{'localId': 'firebase-user-not-a-uuid'}]}
        self.profile = {'fields': {'is_banned': {'booleanValue': False}}}
        self.room = {'fields': {'is_closed': {'booleanValue': False}, 'seat_count': {'integerValue': '8'}}}
        def handler(request):
            self.requests.append(request)
            if request.url.host == 'identitytoolkit.googleapis.com':
                return httpx.Response(self.identity_status, json=self.identity)
            if '/sovera_profiles/' in request.url.path:
                return httpx.Response(200, json=self.profile)
            return httpx.Response(200, json=self.room)
        self.transport = httpx.MockTransport(handler)
    async def call(self, header='Bearer fixture-token'):
        with patch.object(g.httpx, 'AsyncClient', side_effect=lambda **kw: REAL_CLIENT(transport=self.transport, **kw)):
            return await g.authorize_firebase(g.Join(room_id=str(uuid.uuid4())), header)
    async def test_verified_firebase_uid_and_fixed_project(self):
        self.assertEqual(await self.call(), ('firebase-user-not-a-uuid', 8))
        self.assertEqual(len(self.requests), 3)
        self.assertTrue(all('/projects/fixture-project/' in r.url.path for r in self.requests[1:]))
        self.assertTrue(all(r.headers['authorization'] == 'Bearer fixture-token' for r in self.requests[1:]))
    async def test_unverified_token_never_reads_permissions(self):
        self.identity_status = 400
        with self.assertRaises(g.HTTPException) as error: await self.call()
        self.assertEqual(error.exception.status_code, 401)
        self.assertEqual(len(self.requests), 1)
    async def test_banned_account_rejected(self):
        self.profile['fields']['is_banned']['booleanValue'] = True
        with self.assertRaises(g.HTTPException) as error: await self.call()
        self.assertEqual(error.exception.status_code, 403)
    async def test_missing_ban_field_is_not_an_allow(self):
        self.profile = {'fields': {}}
        with self.assertRaises(g.HTTPException) as error: await self.call()
        self.assertEqual(error.exception.status_code, 403)
    async def test_closed_room_rejected(self):
        self.room['fields']['is_closed']['booleanValue'] = True
        with self.assertRaises(g.HTTPException) as error: await self.call()
        self.assertEqual(error.exception.status_code, 403)
    async def test_bad_seat_configuration_rejected(self):
        self.room['fields']['seat_count']['integerValue'] = '101'
        with self.assertRaises(g.HTTPException) as error: await self.call()
        self.assertEqual(error.exception.status_code, 503)
    async def test_missing_credentials_rejected_without_network(self):
        with self.assertRaises(g.HTTPException) as error: await self.call('')
        self.assertEqual(error.exception.status_code, 401)
        self.assertEqual(self.requests, [])

if __name__ == '__main__': unittest.main()
