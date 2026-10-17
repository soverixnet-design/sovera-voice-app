# Invite & referrals

Open Me → Invite & referrals after signing in. A server-generated personal code can be copied, shared as an invitation, or opened in WhatsApp's compose screen. Recipients install Sovera, sign in, and enter the code (or paste the invitation) on the same page. Installation does not automatically redeem the code.

The center shows an exact count of saved code claims and the latest 20 claim dates. It does not expose referred members' private profiles. Each authenticated account can claim one other account's code. Coins, rewards, install attribution and referral leaderboards are not enabled.

Apply REFERRAL_SCHEMA.sql once to an existing Sovera database. It requires sovera_profiles. The deployed Supabase database has this schema. REFERRAL_RLS_TEST.sql verifies privacy, self-referral, duplicates, foreign codes, forbidden deletes and forged identities inside a rolled-back transaction.

The stable public download asset is Sovera.apk on the latest GitHub release. Publish that alias with every subsequent release to keep existing invitations working.

Google/Facebook provider configuration remains pending; guest mode cannot generate or redeem codes. The client requires an authenticated profile and never stores claims locally.
