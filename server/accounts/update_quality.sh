#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run inside your root server SSH session'; exit 1; }
exec 9>/run/sovera-community-update.lock
flock -n 9 || { echo 'Another account update is running'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
TARGET=/opt/sovera-account
DATABASE=/var/lib/sovera-account/profiles.sqlite3
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/be30001a2b9d914ed5f390ccb2271acadb8a16b3
[ -x "$PYTHON" ] && [ -s "$DATABASE" ] && [ -f "$TARGET/server/accounts/control.py" ] || { echo 'Existing account installation required'; exit 1; }
systemctl is-active --quiet sovera-account
STAGE=$(mktemp -d /opt/sovera-quality-stage.XXXXXX)
BACKUP=
CHANGED=0
FILES=(app.py community.py rooms.py wallet.py catalog.py test_wallet.py test_community.py test_catalog.py)
cleanup(){
  result=$?
  if [ "$result" != 0 ] && [ "$CHANGED" = 1 ]; then
    for name in "${FILES[@]}"; do
      if [ -f "$BACKUP/$name" ]; then install -m 644 "$BACKUP/$name" "$TARGET/server/accounts/$name"; fi
    done
    systemctl restart sovera-account || true
    echo 'Previous account code restored. Financial data was preserved.'
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
cp -a "$TARGET/server" "$STAGE/server"
for name in "${FILES[@]}"; do
  curl -fLsS --retry 3 --connect-timeout 10 --max-time 60 "$SOURCE/server/accounts/$name" -o "$STAGE/server/accounts/$name"
done
(cd "$STAGE" && "$PYTHON" -m unittest server.accounts.test_community server.accounts.test_wallet server.accounts.test_catalog server.accounts.test_control server.accounts.test_control_password server.accounts.test_legacy_wallet server.accounts.test_accounts server.accounts.test_voice server.accounts.test_greedy_wallet server.accounts.test_greedy_access -q)
BACKUP=$(mktemp -d /opt/sovera-quality-backup.XXXXXX)
chmod 700 "$BACKUP"
for name in "${FILES[@]}"; do
  if [ -f "$TARGET/server/accounts/$name" ]; then cp -a "$TARGET/server/accounts/$name" "$BACKUP/$name"; fi
done
"$PYTHON" - "$DATABASE" "$BACKUP/profiles.sqlite3" <<'PY'
import os,sqlite3,sys
source=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
destination=sqlite3.connect(sys.argv[2])
try:source.backup(destination)
finally:destination.close();source.close()
os.chmod(sys.argv[2],0o600)
PY
CHANGED=1
for name in "${FILES[@]}"; do install -m 644 "$STAGE/server/accounts/$name" "$TARGET/server/accounts/$name"; done
systemctl restart sovera-account
curl -fSs --retry 8 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8092/sovera/account/health -o "$STAGE/health.json"
"$PYTHON" - "$STAGE/health.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))
assert h.get('ready') is True and h.get('catalog') is True
PY
for path in community/blocks wallet/history catalog; do
 code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8092/sovera/account/$path")
 [ "$code" = 401 ] || { echo 'Authentication check failed'; exit 1; }
done
systemctl is-active --quiet sovera-account
if systemctl is-active --quiet sovera-greedy; then
  curl -fSs --max-time 10 http://127.0.0.1:8080/health -o "$STAGE/greedy.json"
  "$PYTHON" - "$STAGE/greedy.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('walletMode')=='http'
PY
fi
CHANGED=0
echo 'APP_QUALITY_SERVER_READY'
echo "Backup: $BACKUP"
echo 'Wallet balances, game configuration and LiveKit/Caddy configuration preserved.'
