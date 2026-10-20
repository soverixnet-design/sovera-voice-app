# Account profiles during the Firebase transition

## Community restoration (2026-10-20)

The Firebase entrypoint now opens persisted Moments, customer-service requests
with staff replies, official notices, published community events, member lists
and saved room follows. The original four-tab layout, profile artwork, room
cards, frames, gift effects and Greedy launcher are retained.

The matching API is in `community.py`. Requests always derive identity from
the Firebase bearer token. Support requests are private to their author and
assigned staff. `account_staff` starts empty; login and profile edits cannot
assign a staff role. Only an existing trusted server operator may provision
these roles. A support-only role cannot publish notices or events. Published
events are announcements; automated prize settlement is not implemented.

`update_community.sh` installs a reviewed immutable source snapshot, runs the
account/community/wallet tests before changing the service, backs up SQLite
and the existing code, then verifies health and anonymous-access rejection.
Failure restores previous code without overwriting newer database writes.
It preserves existing service credentials, configuration and voice settings.
The script does not grant roles, fabricate user IDs, import wallet balances,
enable paid games, or imply that phone-to-phone voice was verified.

Still required for a complete production release: reconcile the original
wallet/UID mapping, activate and test the Node game with the HTTP ledger
adapter, install the matched API update on the actual server, verify physical
Android audio, and implement paid gift settlement, genuine referral awards,
mutual friendship/CP requests, private messages and automated event rewards.
These remain separate from cosmetic previews. The UI must not call them paid
or complete merely because the Android build succeeds.

Tests: `python -m unittest server.accounts.test_community -v` and
`flutter test test/firebase_community_test.dart`.

This is a separate profile service, not the full app or wallet migration.
Firebase Admin verifies fresh bearer sessions with revocation and disabled-user
checks. The credential needs Auth Viewer only. Profile data stays in a private,
persistent SQLite file on the existing server; Firestore write access is not needed.

GET and PUT `/sovera/account` operate only on the UID from the verified token.
PUT accepts display_name, country (two-letter uppercase code), bio, avatar_url.
No numeric public ID, role, ban flag, balance or entitlement can be supplied.
There is no coin, recharge, game or owner endpoint. Legacy profiles/IDs and coins
are not imported, and this service cannot mark the Food wallet migration ready.

The unit uses systemd DynamicUser, LoadCredential and StateDirectory. It binds
127.0.0.1:8092 only. Do not expose it publicly until its HTTPS reverse proxy is
configured. Never copy the private key into this repository or into an APK.

Deployment prerequisites: verified existing Firebase reader JSON and the staging
venv with FastAPI, firebase-admin and uvicorn. Install app.py and this unit, verify
unit syntax, start it, check `/sovera/account/health`, and verify unauthenticated
`GET /sovera/account` returns 401. It must report wallet=false and games=false.

Run `python -m unittest server.accounts.test_accounts -v` for cross-account
isolation, restart persistence, forged permission rejection and private responses.
The Flutter full-app data stores still need migration; this module does not claim
that login, room creation, profile onboarding or gifts work end-to-end yet.


## Firebase live voice

`update_voice.sh` adds authenticated POST `/sovera/account/voice` using the
existing LiveKit installation, without changing the legacy voice unit. It reads
server-only credentials through systemd EnvironmentFile and requires the
existing `/root/sovera-livekit-secrets.env`. Firebase room names use `fb-<UUID>`
so independent seat reconcilers never alter each other's permissions.

The account service verifies revoked/disabled Firebase sessions, requires a
saved SQLite profile and existing room, and reads seat counts from the server.
Join tokens cannot publish. Speaking requires a seat lease tied to the current
LiveKit participant SID; renew every eight seconds, expiry after 35 seconds.
Backgrounding disconnects local audio. Authentication and lease tests do not
prove two-device audio: verify actual speaking/listening on Android after the
server update and new APK installation. Wallet and games remain disabled.

The updater backs up code, unit and SQLite, validates tests and health, and
restores previous service code on failure. It does not restore the database
over newer profile/chat writes. A successful update prints
`FIREBASE_VOICE_API_READY`. No private key belongs in the app or repository.


## Verified room effects and free XO Duel (prepared, not deployed)

The Firebase account service now includes **room-visible cosmetic effects** and
a persistent **2-player XO Duel**. Both operate on the existing protected
account SQLite database and require a valid Firebase bearer identity.

- `GET /sovera/account/rooms/{room}/people`: current room heartbeats with
  server-owned user IDs and display names.
- `GET /sovera/account/rooms/{room}/effects`: effects from the previous
  15 seconds, with server time; the app polls after joining a room.
- `POST /sovera/account/rooms/{room}/effects`: a verified recipient UID,
  one of rose/heart/sparkle/crown and a request UUID. Both participants must
  be present in the same room. Requests are idempotent and rate-limited.
- `GET /sovera/account/rooms/{room}/duel`: server-authoritative 3×3
  board, player identity, revision and result.
- `POST /sovera/account/rooms/{room}/duel/join`: occupies one of two
  player slots; spectators cannot join a full game.
- `POST /sovera/account/rooms/{room}/duel/move`: a server-checked cell and
  current board revision. Out-of-turn/stale/duplicate moves are rejected.
- `POST /sovera/account/rooms/{room}/duel/restart`: a joined player
  starts a fresh round after a completed match.

The 15-second effect is a **free visual animation**, not a paid gift.
Neither module inserts into a Coin or Diamond ledger, debits the sender,
rewards the recipient, or enables wagering. The health endpoint reports
`room_effects=true`, `free_duel=true`, while `wallet=false` and
`games=false` continue to mean there are no production Coin games.

The Firebase room screen has a Gift Effects action and XO Duel action.
The UI reads real members, game turns and events only from the server; when
the new endpoint is unavailable, it must not claim a completed paid gift.

Run `python -m unittest server.accounts.test_accounts server.accounts.test_voice server.accounts.test_duel -v`
before updating. The existing `server/accounts/update_voice.sh` is pinned
to a reviewed source commit and now copies the new duel module, validates
these tests, backs up the previous service and database, and verifies health.
The updater must be run on the actual host by an administrator with console
access; GitHub source commits alone do not deploy the server.

**Still blocked:** physical two-device voice/audio verification; Coin/Diamond
wallet migration and atomic gift settlement; 16+ full games, matchmaking,
live rankings, room gift-to-avatar effects, device push and release signing.
Do not merge the preview branch with the production main app without
verifying that the matching backend has been deployed and tested.


## One shared game and winner list across all rooms

`server/accounts/global_games.py` provides a **free Global Color Game** with
one SQLite-backed sequence of rounds for the whole Sovera account service,
not a different timer or winner for each phone or room.

- `GET /sovera/account/games/colors`: authenticated shared state, authoritative
  `round`, `phase`, `server_now_ms`, `phase_ends_ms`, verified winners and
  last eight settled results.
- `POST /sovera/account/games/colors/pick`: only a valid signed-in profile can
  choose a color for the current open round. The server locks one color per
  user/round; same-choice retries are idempotent and stale/changed picks fail.
- Each round consists of a **25-second pick**, **10-second reveal** and
  **5-second break**. A single server draw is stored atomically after picking
  closes; winner names and totals are computed from actual persisted picks.
- After downtime, only the last outstanding round is settled and a new round
  begins. No backfilled fabricated draws. On restart the results and picks
  survive as long as the existing account SQLite file stays persistent.
- The Flutter game reads `server_now_ms` and advances a local monotonic clock
  between responses, refreshing approximately once per second. The room and
  directory winner strips refresh every two seconds. This is **near-real-time
  authenticated polling**, not WebSocket push or guaranteed zero-latency sync.
- The global round is shared across all rooms; the older XO Duel is still a
  two-player room game with spectators. The global color result appears on
  the room screen and in the room directory with the same round ID/winner count.
- **No paid betting or prizes are connected**. `wallet=false` and
  `games=false` are intentionally retained in health; the separate
  `global_color_game=true` means only the free shared game is available.
  There is no client-side draw or fake Coin/Diamond settlement.

Run:
`python -m unittest server.accounts.test_accounts server.accounts.test_duel server.accounts.test_global_games server.accounts.test_voice -v`.

The deployment remains **source-ready but not activated on the host** until
an authorized server operator runs the pinned, backup-first updater
`server/accounts/update_voice.sh` on the existing host. Android build/test
completion does not mean that the Firebase-account server is already updated.
The updater checks authentication and health after service restart. Do not
merge this branch into the old Supabase production main without verifying the
Firebase app entrypoint and new server endpoints together.


## Original multiplayer Food Wheel preview

The user's original **ফুড হুইল গেম.html** is now preserved at
`assets/games/food-wheel.html`. All of its 3D wheel, food-item imagery,
result sheet, and visual layout are retained. Both browser-generated rounds,
fake bots, dummy balance, and browser-side winning decisions were replaced
with a restricted `SoveraWheelBridge` that proxies only verified Firebase API
requests from Flutter's local-asset WebView. It never exposes the Firebase ID
token or service credentials to browser JavaScript.

The **same global wheel** is visible to *all authenticated members*, in any
room or in the full-screen lobby. It is not 1v1 and does not require a seat.

- `GET /sovera/account/wheel/state` returns the same room-independent round
  ID, phase, timestamp, outcome, exact wheel stop slot, results history and
  actual signed-in winners. The current person's pick is private.
- `POST /sovera/account/wheel/pick` accepts ONLY one of the original eight
  food names plus the current round number. Each user can pick once per round.
  Repeated same-pick retries are idempotent; changed/late picks are rejected.
- Every global round has 20 seconds to pick, 5 seconds to spin and 5 seconds to
  display results. A backend-generated, SQLite-persisted winning food and
  visual index are reused on every device. The app requests updates about once
  per second and interpolates the visual animation from **server** time.
- Original Salad/Pizza outcomes and their matching food groups are supported.
  The server reports actual winner names based on stored user selections,
  never prefilled bot names or fabricated payouts.
- The original UI opens as a full-screen WebView from the lobby and as a
  64%-height bottom sheet within a voice room; Flutter draws the genuine
  voice seat UI separately.

**Important:** This is a *free connected gameplay preview*, not a real Coin
or Diamond betting product. The chips remain visible as original artwork,
but the client refuses paid bets and the backend does not debit or credit any
wallet. The separate `server/food` monetary ledger is not linked to existing
profile wallets and must not be activated as a second spendable balance.
Atomic migration/ledger reconciliation and administrator approval are
prerequisites for real-money/coin wagers or Diamond prizes.

Tests: `python -m unittest server.accounts.test_food_wheel -v` and
`flutter test test/firebase_food_wheel_test.dart`. Phone-to-phone verification
and authorised server deployment remain necessary. Commits to GitHub are NOT
automatically changes to the protected, running DigitalOcean account service.
