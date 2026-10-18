# Sovera Control — prepared, not activated

Private panel preview: https://sovera-control.soverixnet.chatgpt.site

Production activation is blocked by automatic approval review. Neither the database migration nor the privileged Edge Function has been applied. Existing IDs, permissions and wallet data remain unchanged. Do not treat the preview as a working production control panel. No account has been made Owner.

## Prepared controls

- Eight-digit main IDs starting at 10000001, alongside separately unique VIP IDs (1–7 digits).
- Owner-only staff assignment: manager, admin, agent, room admin, support; individual action permissions, activation/revocation, room scope and quota.
- Staff sign-in from a five-minute, single-use code generated inside the authenticated app. Gateway sessions last 30 minutes. Each API operation rechecks current staff access and suspension.
- Server-side user/VIP lookup, suspension, atomic idempotent recharge, quota accounting, receipts and audit history.
- Saved room settings, published banners/notices, media uploads, asset/catalogue settings, event configuration and saved support replies.
- The updated app reads banners/notices and support replies, displays VIP IDs and staff sign-in, and hides closed rooms.

## Still outside these controls

Live voice, room presence, kicking/muting connected participants, actual gift settlement and targeted live animations, games, automatic ranking/event rewards, actual frame/inventory grants and Diamond exchange still need their application engines. The panel explicitly labels those configuration-only paths.

## Validation

`cd admin/tests && npm ci && npm test` runs an isolated PostgreSQL/PGlite migration test, authorization/RLS/quota/ledger tests, rollback validation, DOM interaction checks, gateway crypto/auth tests and TypeScript checking. All data is synthetic; tests do not contact production services. Real browser rendering, device gallery/audio and real-account multi-user testing remain pending.

The pre-activation rollback restores backed-up original IDs and dependent member-card IDs. It refuses to erase posted recharges or undo new registrations. Once accounting is active, preserve records and use a forward repair instead.

## Activation after explicit approval

1. Confirm the owner's actual signed-in app account. The existing unverified account is not automatically trusted. No unverified or arbitrary account may be promoted.
2. Apply the reviewed `backend/schema.sql` transaction to the selected project, then rerun scoped verification using rolled-back fixtures. Preserve the private ID mapping.
3. Deploy `backend/gateway.ts` as Edge Function `sovera-admin`. It implements its own signed-session and one-time-code authentication; only its service-role calls may execute privileged SQL functions. No service-role key enters the browser or app.
4. Privately assign the verified account as the single Owner. Keep ownership assignment out of public bootstrap endpoints.
5. Test real-account user lookup, a bounded recharge, immediate revocation, VIP uniqueness and receipts before granting other staff access.
6. Publish the corresponding app build only after the schema is active. The current branch is an integration preview, not a production app update.
7. The Site is currently owner-private. Agree on access for other staff before changing its audience. A public sign-in page must still enforce staff authorization at the gateway.

Root `main` and the previously published app have not been replaced by this draft branch.
