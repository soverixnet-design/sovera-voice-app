# Sovera admin on admin.soverixnet.com

This panel uses the Firebase account service and its existing SQLite wallet
ledger. It makes no Supabase requests. Keep the legacy panel and its database
intact until the original account IDs and balances have been reconciled.

Included: single-use native app login codes; 30-minute secure HttpOnly browser
sessions; live permission checks and logout; member lookup; verified-wallet
recharge, receipts and history; agent quotas; owner-managed staff; official
notice/event posts; private support inbox and replies. Recharge retries retain
their request ID across tab refreshes. Missing legacy wallets stay unverified.
Agents cannot grant access; support staff cannot recharge; owner access cannot
be assigned by signup, the browser or profile changes.

DNS: point the `admin` A record at the existing server `206.189.238.27`.
The Caddy block serves this directory and proxies only `/sovera/control/*`
to the existing account service. The voice site is preserved. App bearer-auth
calls remain on `voice.soverixnet.com/sovera/account`. Caddy configuration
must be validated before reload; see https://caddyserver.com/docs/command-line.

Deploy the matched account source, static files and Caddy block using the
pinned installer. It backs up the code, Caddy config, website and database;
failed activation restores code/config without reverting newer user writes.
DNS/HTTPS and the existing Caddy installation are checked before completion.

After installation, a trusted root console operator runs
`provision_owner.py` to list existing Firebase profiles, then chooses the
owner's actual UID with `--uid`. It never picks a user from a display name,
creates a new owner account, or replaces a different existing owner.
The designated owner opens Me → Community admin → Generate admin sign-in
code, then uses that code at the admin domain. Creating a new code invalidates
older unused codes. Code/session secrets are hashed at rest.

Not implemented here: legacy-wallet migration, automatic event prizes,
payments, item purchases, paid gift settlement or game installation. Existing
coin balances must be verified before recharge. Browser session tests and
Android build checks do not prove device Google sign-in or two-device audio.

Tests: `python -m unittest server.accounts.test_control -v` and, in
`admin/tests`, `node selfhost-dom-test.mjs`.
