# Credential installation recovery

Status: local helper tested; NOT run on the production host. No credential is
included. This step does not enable the game, confirm IAM roles, migrate users
or wallets, or prove a successful Firebase connection.

The earlier interactive paste procedure could wait indefinitely without any
feedback. `install_credential.py` instead reports `INPUT_RECEIVED` without
displaying the input, accepts terminal bracketed-paste wrappers, avoids the
canonical terminal line-size limit, restores terminal settings on exit, and
times out after 120 seconds. A complete JSON object needs no final Enter.
Ctrl+C cancels. Never paste a credential into chat or a shell command line.

Run this helper ONLY on the existing trusted server, at a normal shell prompt
after cancelling any older waiting script. Terminal-based entry:

```sh
python3 server/food/install_credential.py
```

Alternatively, if the fresh downloaded JSON was already transferred privately
to that same host, supply its local path with `--source`. Do not put JSON text
in the command or commit it to Git. The helper reads at most 16 KiB and never
logs file contents or raw JSON parser errors.

It checks the expected project/service-account identifiers and PEM delimiters,
and rejects the known exposed key ID. It does NOT cryptographically verify the
private key or check whether Google has disabled it. Google API checks must
follow after installation. Revoke the previously disclosed key in Google Cloud.

Destination: `/etc/sovera-food/firebase-reader.json`, file mode 0600, directory
0700, owned by the invoking user (run as root on the production host). Existing
files are never overwritten. A symlink destination directory is rejected.

`CREDENTIAL_SAVED` means only that this local file was installed. Runtime still
requires a verified Firebase connection and migration of the one authoritative
wallet before activation. Do not set `SOVERA_FOOD_WALLET_READY=1` to bypass that
migration requirement.

Local verification (no real secrets or network required):

```sh
python3 -m unittest server.food.test_install_credential -v
```
