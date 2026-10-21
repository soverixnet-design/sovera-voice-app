# Professional admin delivery — 0.19.0

Implemented in this revision:

- Authenticator TOTP for password and single-use-code admin login, hashed one-use recovery codes, replay prevention, own-session inventory/revocation, bounded login throttling.
- Expiring staff access and capability restrictions enforced on control APIs and native community publishing/support endpoints. Restrictions reduce existing roles; they do not grant owner access.
- Owner-only virtual currency reports, 30-day activity chart/table, observed user agent/network history, audit/ledger CSV export, member filters before pagination, and large adjustment visibility. These are not cash-profit reports. Observed network fingerprints do not prove physical device identity.
- Central room closure/ban/reopen, directory and voice renewal enforcement, plus best-effort live RTC disconnect with explicit pending status.
- Support status, assigned staff and internal notes; future in-app notices with a scheduled worker.
- Owner-published VIP/SVIP Coin purchases with stable transaction IDs, safe retry/cancellation, membership expiry and included timed collection assets.
- Opt-in qualified referrals. Existing accounts are not reclassified as new; qualification uses verified recharge receipts and excludes refunded orders.
- Manual payment orders: references do not credit Coins until owner verification; approval/refund Coin reversal are atomic and idempotent. Cash collection/refunds must be verified separately with the merchant provider.
- Immutable future monthly agency terms, recorded membership intervals, actual qualifying gift Diamond targets, Coin salary/commission reports and owner-reviewed once-only closed-month settlement. This is not a cash payout system.
- Daily/weekly/calendar-month recurring rewards and optional automated qualified claims. A repeat can be stopped without cancelling already-promised prizes.
- Locked systemd maintenance worker and daily SQLite online backup copies, SHA-256 manifests, integrity checks, 14-snapshot retention and owner-visible worker/backup state. The updater backs up previous code and restores it on failure; live wallet transactions are preserved.

## Verification and deployment limits

The release workflow runs Python account/voice tests, Node admin/Greedy tests, Flutter analyze/tests and builds Android APKs. This does not prove real-device microphone continuity or successful live deployment.

The owner must run the release's pinned `update_room.sh` in the existing root server session. This workspace has no VPS SSH credentials. No live balance or economic offer was changed here. Referral rewards remain disabled until configured; prices, commissions and rewards are owner-controlled.

Still dependent on configuration or separate implementation:

- Google sign-in requires a stable release signing identity and corresponding Firebase/OAuth certificate configuration, followed by phone verification. This revision does not claim to fix Google sign-in.
- Automatic merchant payment verification/cash refunds need merchant credentials and signed provider webhooks. The delivered workflow is explicitly manual verification.
- Background push delivery needs FCM/APNs configuration and device tokens. Scheduled notices currently appear inside the app.
- Extra animation formats and entry audio are not introduced in this revision. Existing supported artwork/animation and entry scenes remain available.
- Backup verification checks independent database copies. A coordinated multi-database restore drill and production recovery runbook validation remain operator work; no live restore was attempted.
- Stronger automated anomaly detection beyond large-adjustment visibility needs owner-defined thresholds and alert delivery configuration.
- Live installation, current VPS health, Google sign-in and two-device/background voice/seat persistence require real device verification.
