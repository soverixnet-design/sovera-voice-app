#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'STOP: root console required'; exit 1; }
[ -s /etc/sovera-food/firebase-reader.json ] || { echo 'STOP: credential missing'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
[ -x "$PYTHON" ] || { echo 'STOP: staging Python missing'; exit 1; }
[ ! -e /etc/systemd/system/sovera-account.service ] || { echo 'STOP: account service already installed'; exit 1; }
[ ! -e /opt/sovera-account ] || { echo 'STOP: account directory already exists'; exit 1; }
[ -z "$(ss -H -ltn 'sport = :8092')" ] || { echo 'STOP: port 8092 in use'; exit 1; }
"$PYTHON" -c 'import firebase_admin, fastapi, httpx, uvicorn'
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/4a85e7591b48bb14cf7789a2577bf1d2b9a90b4f/server/accounts
STAGING=$(mktemp -d /opt/sovera-account-install.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/server/accounts"
for file in app.py test_accounts.py sovera-account.service; do
 curl --fail --silent --show-error --connect-timeout 10 --max-time 45 "$SOURCE/$file" -o "$STAGING/server/accounts/$file"
done
(cd "$STAGING" && "$PYTHON" -m unittest server.accounts.test_accounts -v)
# Installation files are readable by the service's temporary, unprivileged UID.
chmod 755 "$STAGING" "$STAGING/server" "$STAGING/server/accounts"
chmod 644 "$STAGING/server/accounts/"*
mv "$STAGING" /opt/sovera-account
install -m 644 /opt/sovera-account/server/accounts/sovera-account.service /etc/systemd/system/sovera-account.service
systemd-analyze verify /etc/systemd/system/sovera-account.service
systemctl daemon-reload
systemctl enable --now sovera-account
curl --fail --silent --show-error --retry 8 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8092/sovera/account/health
CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 http://127.0.0.1:8092/sovera/account)
[ "$CODE" = 401 ] || { echo 'STOP: account protection check failed'; systemctl stop sovera-account; exit 1; }
printf '\nACCOUNT_API_READY\n'
