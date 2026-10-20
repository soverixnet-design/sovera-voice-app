# Sovera Greedy: replace legacy games without touching the voice app or wallet

## Current code and what is actually online

- Firebase app entry point: `lib/firebase_login_main.dart`; restored four-tab
  UI: `lib/firebase_sovera_home.dart`.
- Greedy buttons: lobby `lib/firebase_sovera_home.dart` and
  `lib/firebase_rooms.dart`, and inside each `FirebaseRoomChat`.
- Greedy WebView `lib/firebase_greedy_wheel.dart` only navigates to the
  pinned HTTPS path `https://voice.soverixnet.com/greedy/` **after** a short
  signed game-only JWT is issued by the Firebase account service.
- Token minting: `POST /sovera/account/greedy/access`. The
  `server/accounts/greedy_access.py` implementation verifies user identity
  and a saved account profile, then refuses to mint until
  `SOVERA_GREEDY_ENABLED=1`, `SOVERA_GREEDY_WALLET_VERIFIED=1`,
  strong secret and a valid HTTPS game URL are all present.
- Original user-provided art: `greedy-game.zip`, with `greedy-game/index.html`,
  `style.css`, `game.js` and 8 WebP items. It is **not yet present** as a
  full set of Android/GitHub assets and the independent Node backend is NOT
  deployed on the existing DigitalOcean droplet by the GitHub commits.
- `server/food` and `server/accounts/food_wheel.py` are legacy/staging
  independent game engines. They do NOT share the production Sovera wallet
  and MUST NOT be combined to mint additional spendable balances.
- The real Coin wallet in older app code uses Supabase's
  `sovera_wallet_balances`/`sovera_wallet_entries`, whereas the new game
  session uses Firebase UID. The correct cross-auth ownership mapping has
  **not** been verified. Do not guess it or credit the wrong wallet.

## Planned one shared Greedy game across all rooms

One Greedy game process owns a single global round ID, start/end times,
result/seed, WebSocket updates and settlement queue for all room and lobby
viewers. A room is only the *entry point*, not a separate round. Games are
not 1v1. Never generate any client-local result, fake opponent, fake bonus,
fake balance or invented winner.

Official flows:
1. Sign in with Firebase and save one profile; app POSTs to Greedy access
   with a verified Firebase bearer ID token.
2. Backend issues a short Greedy-specific HS256 JWT (5 minutes), with
   authoritative UID and display name. Only that JWT reaches the game WebView.
3. WebView opens a pinned HTTPS origin under `/greedy/` and WebSocket
   `/greedy/ws`; it sends `{"t":"auth","token":"..."}` **as the first
   WebSocket frame**, never in URL query strings or server/proxy logs.
4. Node validates JWT before admitting the socket. It owns all rounds,
   timers, betting closure, result derivation, leaderboard and payout jobs.
   Native Flutter requests a fresh JWT when the game reports `auth_failed`.
5. A verified, idempotent **single Sovera wallet** handles signed requests
   `/balance`, `/debit`, `/credit` using the same user identity and
   one serializable transaction boundary. Refunds require a matching applied
   debit. Prevent double charges, double payout, forged/late bets, and frozen
   account betting. Coins and Diamonds are distinct.
6. The original visual assets and animations render results provided only
   by the server; players inside and outside voice rooms see identical
   round ID, timer, winner and shared total data.

## Release/deployment safety

A reviewed Greedy Node source-and-art ZIP with original WebP artwork, Node
WebSocket auth, safe path handling and a preflight script can be installed
**after** the wallet adapter is verified. Do not run Node games as root;
bind 127.0.0.1:8080, configure HTTPS reverse proxy under /greedy/, retain
existing `/sovera/account/` and LiveKit voice configuration, and take backups
before updating any systemd/nginx service. Never set `DEMO_AUTH=1` on a
public deployment. Local demo balances are not production Coins.

Use a staging wallet first to prove two users share a result, then validate
wallet idempotency, concurrent bets, forced disconnects, auth expiry/refresh,
backups, restore, and multi-device audio. Do not flip paid-game feature flags
or advertise winnings until these checks and applicable permissions are complete.

**GitHub CI tests verify code/build**, not that the Node game exists on
DigitalOcean or that anyone's real balance has been safely credited/debited.
