# Sovera current status — 18 October 2026

## Added in this update

- Server-generated unique six-digit public IDs, starting at 100001. Existing profile IDs were remapped in creation order and dependent member/seller records cascade with them. UUID account identity is unchanged. The identity is GENERATED ALWAYS; clients cannot choose an ID. IDs increase in allocation order; failed transactions may leave gaps, and deleted IDs are not reused. Six-digit allocation stops at 999999.
- Tapping a member name in People opens their shared profile, with stored Follow/Unfollow, direct Chat, received gifts and profile medal styles. Own profile has an Open member profile button; signed-in saved-room occupied own seats open the same member page. Live room occupants remain unavailable until room presence is implemented.
- Private text chat is persisted on the server (new sends require the recipient to keep their member card discoverable), limited to the two participants by RLS and refreshed every four seconds while foregrounded. Failed sends retain the draft. Latest 200 messages are shown; the Messages tab now opens a private conversation inbox. Notifications, older-message pagination, attachments, blocks and reports remain pending.
- Public profile medals can be equipped and saved to the account; these are decorative styles, not awarded rank or staff permissions. Private profile name/photo/bio updates synchronize to existing shared cards. Public discoverability remains opt-in.
- Recent received gifts have a read-only server showcase. The app cannot create received gifts or credit itself. No records are fabricated. Actual gift settlement must populate this showcase when implemented.

## Still required

1. Live RTC voice/microphone and two-device seat/presence synchronization. Local mic and seats are previews.
2. Shared room chat, invitations/deep links and cross-room gift/winner banners.
3. Gift recipients, multi-select/All, atomic Coins-to-Diamonds settlement, targeted animation and gift ledger integration.
4. Admin user lookup/recharge, sub-admin coin quotas/transfers, approvals/history and 100 Diamonds to 70 Coins exchange.
5. Game server rounds/bets/settlement, consistent timers, Ludo/Carrom and other requested games. Current Games area is a placeholder.
6. Daily/weekly/monthly rankings, events, reward settlement and room leaderboards.
7. Real friendship/CP requests, persisted frames/entry inventory, awarded medals and permission-controlled staff roles.
8. Unread counts/push notifications, media uploads beyond room picture, admin banners/notices, account deletion, final policies and physical-device testing.
9. Social login provider/account configuration must be verified on real accounts; a built login button does not prove external provider approval.

Prior room-media update remains: gallery room picture upload, animated gift previews, entry sounds and mute controls. Android/iOS compile and widget tests do not prove two-device voice or audible device playback.
