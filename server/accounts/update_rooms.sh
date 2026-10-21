#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'STOP: root console required'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
TARGET=/opt/sovera-account/server/accounts
[ -f "$TARGET/app.py" ] || { echo 'STOP: install the account API first'; exit 1; }
[ -s /var/lib/sovera-account/profiles.sqlite3 ] || { echo 'STOP: existing profile database missing'; exit 1; }
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/7d39d176d13ee0d943ddfb005d7820e3b18c6944/server/accounts
STAGING=$(mktemp -d /opt/sovera-rooms-update.XXXXXX)
CHANGED=0
BACKUP=
cleanup(){
 code=$?
 if [ "$code" != 0 ] && [ "$CHANGED" = 1 ]; then
  cp "$BACKUP/app.py" "$TARGET/app.py"
  if [ -f "$BACKUP/rooms.py" ]; then cp "$BACKUP/rooms.py" "$TARGET/rooms.py"; else rm -f "$TARGET/rooms.py"; fi
  if [ -f "$BACKUP/test_accounts.py" ]; then cp "$BACKUP/test_accounts.py" "$TARGET/test_accounts.py"; fi
  systemctl restart sovera-account || true
  echo 'UPDATE_FAILED: previous service code restored'
 fi
 rm -rf "$STAGING"
}
trap cleanup EXIT
mkdir -p "$STAGING/server/accounts"
for file in app.py rooms.py test_accounts.py; do
 curl --fail --silent --show-error --connect-timeout 10 --max-time 45 "$SOURCE/$file" -o "$STAGING/server/accounts/$file"
done
(cd "$STAGING" && "$PYTHON" -m unittest server.accounts.test_accounts -v)
BACKUP=$(mktemp -d /opt/sovera-account-backup.XXXXXX)
chmod 700 "$BACKUP"
cp -a "$TARGET/". "$BACKUP/"
"$PYTHON" - "$BACKUP/profiles.sqlite3" <<'PY'
import sqlite3,sys,os
source=sqlite3.connect('file:/var/lib/sovera-account/profiles.sqlite3?mode=ro',uri=True)
dest=sqlite3.connect(sys.argv[1])
try:
 source.backup(dest)
finally:
 dest.close();source.close()
os.chmod(sys.argv[1],0o600)
PY
CHANGED=1
for file in app.py rooms.py test_accounts.py; do
 install -m 644 "$STAGING/server/accounts/$file" "$TARGET/$file"
done
systemctl restart sovera-account
curl --fail --silent --show-error --retry 8 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8092/sovera/account/health -o "$STAGING/health.json"
"$PYTHON" - "$STAGING/health.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))
assert h.get('ready') is True and h.get('rooms') is True and h.get('chat') is True
assert h.get('wallet') is False and h.get('games') is False
PY
CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 http://127.0.0.1:8092/sovera/account/rooms)
[ "$CODE" = 401 ] || { echo 'STOP: room access protection check failed'; exit 1; }
printf '\nROOM_CHAT_API_READY\n'
echo "Backup: $BACKUP"
