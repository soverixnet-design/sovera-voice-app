# Sovera Control

Live owner-private panel: https://sovera-control.soverixnet.chatgpt.site

The base schema and authenticated gateway were activated on 2026-10-18 after explicit authorization. The verified account originally numbered 100001 is now 10000001 and is the single active Owner. Main app release remains separate from this integration branch.

## Module coverage

| Requested module | Implemented behavior / remaining dependency |
| --- | --- |
| 1 User management | Main/VIP lookup, profile and wallet view, suspension, scoped permissions |
| 2 Room moderation | Saved room settings, scoped closure, attendance heartbeat monitor and violation reports; live audio moderation requires RTC engine |
| 3 Finance | Private paginated Coin/Diamond ledger, filters, recharge receipts and immutable activity trail |
| 4 Resellers | Owner-approved seller directory and applications; recharge quotas remain separate staff permissions |
| 5 Store/settings | Published catalogue, exchange settings, expiring item grants; paid item purchases and effect/audio playback are pending |
| 6 Banners/notices | Published app content and media uploads |
| 7 Events | Event configuration only; automated ranking/settlement engine is pending |
| 8 Support | Saved official/recharge tickets and replies |
| 9 Analytics | Real saved-account, ledger, posts and attendance totals; cash revenue/payment receipts and performance telemetry are not connected |
| 10 Seller visibility | Owner-controlled Show/Hide, enforced by published-seller RLS |
| 11 Role-based items | Explicit inventory.grant permission, expiring grants, issuer/Owner revocation and audit |
| 12 Daily login | Once per UTC day, atomic coin ledger + optional expiring frame; disabled by default until Owner configures |
| 13 Notifications | Notices/update/notification content records; device push delivery needs an FCM/APNs provider and client registration |
| 14 Moments | Saved text feed, own soft-delete, reports and admin hide/restore; image stories are pending |
| 15 Room display | Existing gallery room image on directory card; heartbeat occupancy, country-code flags on profile/feed; no claim of established audio |
| 16 Onboarding | Profile gallery, name/bio/city/country editing and first-login form; public photo disclosure |
| 17 Connections | Consent-based friend/CP requests, one accepted CP partner, ending connections; Love gift totals need gift settlement |
| 18 Profile layout | Visible wallet balance, then reseller center, then friendship/CP/Love |

## Security and testing

All privileged admin mutation RPCs are service-role-only and recheck active staff on every request. Never publish service credentials. User operations use an authenticated wrapper around a private function that validates the signed-in actor, bans, wallet state, ownership and consent. New tables use RLS; clients cannot grant their own items or credit their own wallets directly.

Run `cd admin/tests && npm ci && npm test` for isolated SQL/RLS/accounting/consent, DOM and gateway tests. Android CI analyzes and tests Flutter before producing an integration APK. Browser/device gallery, push and multi-device voice testing remain separate. Financial ledgers must be preserved; do not apply the old pre-activation rollback after real transactions or after module activation.

Base activation uses backend/schema.sql once. Additional modules use backend/modules.sql once, after the base. Both must exist before installing this branch's app. Daily rewards and exchange are initially disabled. The app owner chooses rates, reward amounts and staff permissions in the panel.
