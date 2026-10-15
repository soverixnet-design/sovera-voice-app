# Required production implementation

Do not attach this new project to the existing Firebase application without checking its configuration and access policies.

1. Choose one identity provider and validate its tokens server-side. Users default to user role; privileged roles require explicit owner assignment.
2. RTC: authorize room membership and speaker role, issue short-lived Agora tokens on the server, implement seat events and reconnection. Test voice between two physical devices, including Android background/foreground and audio routing.
3. Persist all room changes and enforce ownership. Use a shared room revision and authoritative server time; never trust actor UID from a client payload.
4. Use a ledger for Coins and received Diamonds. Server verifies gifts, debits Coins, credits recipient Diamonds and records an idempotent transfer atomically. Multi-recipient gifts calculate the full cost before debit. Exchange 100 Diamonds to 70 Coins with an atomic transaction. Self-gifts, if enabled, must not generate referral/commission abuse.
5. Payments only credit after provider verification and signature checks; enforce unique gateway transaction IDs. Keep SDK certificates and merchant secrets off-device.
6. Admin: owner-controlled roles, recharge-only permission, transaction audit log, quota-limited sub-admin pool, UID search, user presence, gifts/assets, notices and support.
7. Ranking/event engine: server-derived daily and weekly periods, one settlement per event, authoritative broadcast and 10–15-second result banners.
8. Games, PK, agencies, host payouts, support and Moments require complete APIs, data policies and integration tests before being described as working.
9. Add complete English/Bangla localization with a persisted language selector. This preview currently supplies English only.
10. Restrict storage uploads by file type/size, verify ownership and permissions, and provide account deletion and privacy/terms flows.
