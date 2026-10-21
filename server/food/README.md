# Food wheel server staging module

Status: tested source, NOT deployed. The uploaded HTML remains a demo and is
not connected to this service. There is no new APK or live coin settlement.

## Included
- `engine.py`: persistent SQLite rounds, bets and append-only wallet ledger.
  `BEGIN IMMEDIATE` serializes debit/check/insert, settlement is atomic, unique
  references prevent duplicate payouts. Concurrent duplicate requests return
  the original bet. Amounts are integer coins; returns are gross coin payouts
  (not Diamonds). The app's Diamond conversion must not run on these payouts.
- 30s betting, 8s spin, 5s wait. No seed/result exists until betting closes.
  Seed is generated with `secrets.token_hex(32)` after close; SHA256 rejection
  sampling selects exact inverse-multiplier weights. This is NOT a precommitted
  provably-fair scheme; `seed_hash` is a post-draw audit record only.
- Multipliers are snapshotted per round. The owner-only config endpoint changes
  next-round multipliers; weights remain inverse multipliers. Independent odds
  weights/target-RTP controls and the admin-panel form are still pending.
- Default multipliers 45,25,15,10,5,5,5,5 give every single-slot bet gross RTP
  450/463 = 97.192224622%. A short session is not guaranteed this return.
- Server autoplay starts on the next round, max 100 rounds; no funds means stop.
- `app.py`: authenticated REST and private WebSocket factory. Body does not
  accept user ID, balance, time or result. WebSocket authenticates in its first
  frame and revalidates identity before each snapshot. Server recovery creates
  one new round at current time, without inventing missed rounds.
- `client.js`: same-origin transport, bearer auth, retry keys, in-flight tap
  deduplication, server-time countdown anchored to performance.now. It does not
  run random draws, add coins, settle bets, fabricate rankings or loop autoplay.

## Required before activation
1. Supply async `verify_identity(token)->uid` and `require_owner(uid)->True` to
   `create_app(engine, verify_identity, require_owner)`. Verification must enforce
   issuer/audience/expiry and account bans/disablement; owner permission is read
   from the server. No placeholder identity adapter is provided.
2. Migrate the app wallet into the SAME authoritative ledger or port this engine
   into the current wallet transaction boundary. This dedicated SQLite ledger
   starts empty and must never be used as a second independent spendable balance.
   `Engine.credit` is trusted adapter code only, not a public recharge endpoint.
3. Autoplay is disabled by default. Supply a trusted synchronous
   `can_autoplay(uid)` policy to Engine to enable it. This is rechecked every
   round alongside funds; it must enforce account bans and revocation policy.
4. Deploy on the existing host with a persistent protected local disk, backup,
   HTTPS, rate limits and bounded WebSocket connections. No network filesystem,
   ephemeral disk or multi-host SQLite. SQLite is a single-host staging design;
   move to the shared wallet database transaction system for horizontal scaling.
5. Serve `client.js` same-origin, replace demo functions (place/pick/settle,
   localStorage balance, fake rankings, add-coins button, local autoplay and fake
   loading delay), wire actual app identity bridge and result animation. Use
   `textContent` for server/profile strings. Reconnect refreshes state/history;
   deduplicate animations by round. Do not use the HTML demo with real balances.
6. Public name/avatar resolution, WIN threshold, admin form, independent odds,
   operational monitoring, authenticated two-device testing remain pending.

## API
GET `/food/state`, POST `/food/bet` `{round,slot,amount}` plus `Idempotency-Key`,
GET `/food/history` (last 30 rounds with your bets), POST `/food/auto`
`{slot,amount,rounds}` (0 stops), PUT `/food/admin/config` `{slot:multiplier,...}`.
Bearer auth required on all routes. State includes `serverNow`/`endsAt` in Unix
milliseconds, last eight slots, private balance/bets, current result, top3.
Names/avatars are null until a trusted profile lookup is connected.
WebSocket `/food/events`: first frame `{"authorization":"Bearer ID_TOKEN"}`;
state/round_start/round_result/big_win events. No credentials in query strings.

Tests: `python -m unittest server.food.test_food -v` after installing the same
FastAPI/httpx versions pinned in the existing CI workflow. No live funds needed.


## Firebase adapter added
`identity.py` implements token verification with `check_revoked=True`, disabled
account and strict `sovera_profiles/{uid}.is_banned == false` checks. Owner
permission requires the Admin-only custom claim `sovera_owner: true`; an editable
profile role never grants access. SDK failures deny access without exposing SDK
error bodies. `runtime.py` wires this adapter but refuses startup until the one
wallet migration is explicitly confirmed and an existing absolute wallet DB path
is supplied. ADC must be installed securely on the existing host; no new server
credentials have been generated or committed.

Live setup observed 2026-10-19: default Firestore Standard database created in
asia-south1 on Spark with production rules denying all client reads/writes.
It is EMPTY; profiles/rooms/wallet data have NOT been migrated. No new app auth
flow, owner grant, paid plan, server deployment or real coin game activation was
performed. SSH to the existing host is currently unreachable from this runtime,
and its DigitalOcean web console returns Site Unavailable in this cloud browser.
