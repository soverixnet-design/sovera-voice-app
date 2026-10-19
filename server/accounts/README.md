# Account profiles during the Firebase transition

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
