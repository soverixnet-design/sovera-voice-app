# Sovera architecture: Firebase ONLY for login

This is the agreed production design. The original Sovera room/avatar/frame
styling is unchanged.

| Capability | Authoritative owner |
|---|---|
| Google/email sign in, Firebase ID token issuance | Firebase Authentication |
| Session verification/revocation on API calls | Firebase Admin on Sovera server |
| Profile name/bio/country/room-owner flag | Sovera account backend (SQLite) |
| Voice seats, room presence, voice JWT permissions | Sovera account backend + LiveKit |
| Room messages, notices, frames, avatar references | Sovera server (some APIs pending) |
| Shared Greedy game round, winner, timing, result | One Sovera game server (deployment pending) |
| Coins/Diamonds, gifts, recharge, payouts | ONE Sovera backend ledger (wallet migration pending) |
| Admin approval, roles, recharge audit | Server only (admin migration pending) |

Firebase **Realtime Database, Firestore, Storage and client-side balances are
not part of this new application's account/data flows**. Firebase Auth is not
a wallet. The account service validates its bearer ID token server-side, then
chooses the account UID. The client cannot supply UID, role, balance, round
result, winning amount or game end time.

App entry point: `lib/firebase_login_main.dart`; restored UI:
`lib/firebase_sovera_home.dart`; isolated original visuals:
`lib/sovera_visuals.dart`. These files do not import the former Supabase
`lib/main.dart`. Other historical Supabase modules remain in the repository
for rollback and historical audit; **do not use them as a live data source for
Firebase-authenticated users**.

Server wallet APIs:
- `GET /sovera/account/wallet` returns either an explicitly **not_migrated**
  wallet with NULL balances, or only a server-verified linked ledger balance.
- `GET /sovera/account/wallet/history` returns only that Firebase UID's
  trusted ledger records. The public API exposes NO balance write, credit,
  debit, exchange or recharge endpoint.
- Account wallet links use a unique source reference so the same legacy
  account cannot be assigned to two Firebase UIDs accidentally.
- `canSpend=false` until trusted atomic settlement is connected to the
  authoritative ledger. The game access endpoint also enforces this gate,
  even if environment switches are mistakenly enabled.

**Do not mark a wallet migrated or import balances solely from login.**
A trusted operator must independently confirm the old ledger's identity
mapping, transaction history and credits, then reconcile with the single
new ledger. No fabricated 0 Coins or Diamonds. Existing user balances must
not be overwritten. A Firebase sign-in does not automatically create money.

The DigitalOcean droplet currently runs an older deployed account service.
GitHub modifications and CI passing do NOT deploy these newer APIs. Use a
backup-first server update after green Python tests, app tests and a
reconciliation plan; compare the live schema before touching wallets. Test
two-phone voice and multiuser Greedy rounds separately. Real coin betting
requires a unified atomic debit/outcome/credit transaction and any applicable
permissions.
