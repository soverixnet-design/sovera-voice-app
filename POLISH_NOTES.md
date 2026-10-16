# Sovera 0.12

- Sapphire/gold bevel seats with a new sofa icon, raised platform and own-seat mute overlay. The large static host illustration is removed to move seats upward.
- Microphone control changes a visual preview state only; RTC audio and remote mute presence are still not connected.
- Back, Minimize, Frames, Seat settings and Leave use dimensional room controls. Minimize preserves the local seat, partner preview, microphone indicator and local chat until resumed from Home. App restart clears this draft.
- Smaller 72px level badges, refreshed navy/violet/cyan/pink palette, and six staff/host medal designs. Medal selection is local decoration and never changes account roles or verified levels.
- People & following persists user follows under RLS. A separate opt-in member card shares only a display name and numeric ID with signed-in users. Existing private profiles remain private; directory visibility defaults off. Search by name/ID, follow and unfollow are implemented; there are no invented members or follower counts.
- Google provider setup remains required for actual sign-in. Live voice, relationship acceptance, gifting and payments are still pending.

Database SQL and rollback verification: PEOPLE_SCHEMA.sql and PEOPLE_RLS_TEST.sql. The rollback test covers hidden-card access, valid follow/unfollow, a hidden target and a forged follower ID. Unrelated EarnBD schema is untouched.
