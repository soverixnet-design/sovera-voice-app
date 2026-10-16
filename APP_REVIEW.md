# Sovera 0.9.1 review

Reviewed entry/auth, home, room cards and search, Moments, Messages/support, profile/levels, reseller, seller directory, wallet/history, rankings/events, cosmetics/medals and room/gift previews.

## Corrected

- Empty bios can be saved; cancelling either edit dialog still cancels the edit.
- A token refresh keeps Home mounted instead of discarding in-progress local state.
- Guest room filters use All / Following / New; New reverses creation order. Search ignores surrounding whitespace and has a clear button.
- Returning to Home resets the banner indicator together with the banner page.
- Removed the empty Gallery destination, unavailable room invite action, inert room chat filter chips and duplicate gift categories that showed identical collections.
- Gift collection displays unknown balance rather than an invented zero. Its action opens a visual preview instead of an unavailable Send operation.
- Empty seats no longer expose fake account levels or gift actions.
- Event pages and seat/profile sheets scroll on short screens. Gift footer wraps and community room tools wrap on narrow screens.
- Room directory ignores stale refresh results.
- Settings version and early-access terms match the current build and stored-account features.

## Working scope

Local UI: guest room creation, seat layout selection/save, local chat/Moments drafts, room follows, social/cosmetic previews, theme/medal selection and finite arrival previews.

Connected read/write paths: authenticated own profile, room creation/settings and follows, private support requests, reseller applications and owner-assigned status/quota reads. Wallet balances/history are read-only and ledger-derived; published seller listings support server-side search and pagination. Prior wallet RLS tests verified owner isolation and denied client credits/approvals.

## Still unavailable

Google OAuth provider configuration is still required for real sign-in. No live voice/RTC, cross-device seating/chat, gift settlement, payment/recharge transfers, Diamond exchange, actual friendships/CP invitations, live rankings/events, private messaging, photo gallery or account-deletion endpoint is implemented. Games remain a clearly labelled placeholder as requested. Real seller/profile/wallet records are not fabricated. Production terms/privacy text still require owner preparation.

UI tests and render captures verify the supported preview paths, not two-device audio or real payments. Android and iOS simulator builds do not constitute physical-device testing.
