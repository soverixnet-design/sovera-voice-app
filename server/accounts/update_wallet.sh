#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run inside the root server SSH session'; exit 1; }

exec 9>/run/sovera-community-update.lock
flock -n 9 || { echo 'Another server update is running'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
TARGET=/opt/sovera-account
WEB=/opt/livekit/caddy_data/sovera-control
DATABASE=/var/lib/sovera-account/profiles.sqlite3
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/10d243d401c71d3df1dde83e175abe8e12f34868
[ -x "$PYTHON" ] && [ -f "$TARGET/server/accounts/control.py" ] && [ -f "$WEB/app.js" ] && [ -s "$DATABASE" ] || { echo 'Install the existing self-hosted admin first'; exit 1; }
systemctl is-active --quiet sovera-account
STAGE=$(mktemp -d /opt/sovera-wallet-stage.XXXXXX)
BACKUP=
CHANGED=0
FILES=(app.py control.py rooms.py catalog.py test_catalog.py wallet.py import_legacy_wallet.py test_legacy_wallet.py)
STATIC=(app.js style.css)
cleanup(){
  result=$?
  if [ "$result" != 0 ] && [ "$CHANGED" = 1 ]; then
    for name in "${FILES[@]}"; do
      if [ -f "$BACKUP/$name" ]; then install -m 644 "$BACKUP/$name" "$TARGET/server/accounts/$name"; else rm -f "$TARGET/server/accounts/$name"; fi
    done
    for name in "${STATIC[@]}"; do install -m 644 "$BACKUP/$name" "$WEB/$name"; done
    systemctl restart sovera-account || true
    echo 'Update failed; previous admin code restored. User data was preserved.'
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
"$PYTHON" -m pip install --disable-pip-version-check Pillow==12.3.0
cp -a "$TARGET/server" "$STAGE/server"
for name in "${FILES[@]}"; do
  curl -fLsS --connect-timeout 10 --max-time 45 "$SOURCE/server/accounts/$name" -o "$STAGE/server/accounts/$name"
done
for name in "${STATIC[@]}"; do curl -fLsS --connect-timeout 10 --max-time 45 "$SOURCE/admin/selfhost/$name" -o "$STAGE/$name"; done
(cd "$STAGE" && "$PYTHON" -m unittest server.accounts.test_legacy_wallet server.accounts.test_control server.accounts.test_control_password server.accounts.test_catalog server.accounts.test_accounts server.accounts.test_community server.accounts.test_wallet server.accounts.test_greedy_wallet server.accounts.test_greedy_access server.accounts.test_duel server.accounts.test_global_games server.accounts.test_food_wheel -q)
BACKUP=$(mktemp -d /opt/sovera-wallet-backup.XXXXXX)
chmod 700 "$BACKUP"
for name in "${FILES[@]}"; do
  if [ -f "$TARGET/server/accounts/$name" ]; then cp -a "$TARGET/server/accounts/$name" "$BACKUP/$name"; fi
done
for name in "${STATIC[@]}"; do cp -a "$WEB/$name" "$BACKUP/$name"; done
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
h=json.load(open(sys.argv[1]));assert h.get('ready') is True and h.get('catalog') is True
PY
for path in catalog rooms; do
 code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8092/sovera/account/$path")
 [ "$code" = 401 ] || { echo 'Account protection check failed'; exit 1; }
done
code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8092/sovera/control/catalog -H 'Host: admin.soverixnet.com')
[ "$code" = 401 ] || { echo 'Admin catalog protection check failed'; exit 1; }
for name in "${STATIC[@]}"; do install -m 644 "$STAGE/$name" "$WEB/$name"; done
curl -fSs --max-time 15 https://admin.soverixnet.com/app.js -o "$STAGE/live.js"
grep -Fq 'Gallery image / animation' "$STAGE/live.js"
CHANGED=0
echo 'WALLET_MIGRATION_TOOLS_READY'
echo "Backup: $BACKUP"
echo 'The legacy wallet still needs its private, verified snapshot imported from the root console.'
