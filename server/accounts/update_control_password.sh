#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run inside the root server SSH session'; exit 1; }
[ -t 0 ] || { echo 'Interactive console required to set your password'; exit 1; }
exec 9>/run/sovera-community-update.lock
flock -n 9 || { echo 'Another server update is running'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
TARGET=/opt/sovera-account
WEB=/opt/livekit/caddy_data/sovera-control
DATABASE=/var/lib/sovera-account/profiles.sqlite3
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/437fb24b87963c0f171c230b598234b242a964e1
[ -x "$PYTHON" ] && [ -f "$TARGET/server/accounts/control.py" ] && [ -f "$WEB/app.js" ] && [ -s "$DATABASE" ] || { echo 'Install the existing self-hosted admin first'; exit 1; }
systemctl is-active --quiet sovera-account
STAGE=$(mktemp -d /opt/sovera-password-stage.XXXXXX)
BACKUP=
CHANGED=0
FILES=(control.py control_password.py provision_password.py test_control_password.py)
cleanup(){
  result=$?
  if [ "$result" != 0 ] && [ "$CHANGED" = 1 ]; then
    for name in "${FILES[@]}"; do
      if [ -f "$BACKUP/$name" ]; then install -m 644 "$BACKUP/$name" "$TARGET/server/accounts/$name"; else rm -f "$TARGET/server/accounts/$name"; fi
    done
    install -m 644 "$BACKUP/app.js" "$WEB/app.js"
    systemctl restart sovera-account || true
    echo 'Update failed; previous admin code restored. User data was preserved.'
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
cp -a "$TARGET/server" "$STAGE/server"
for name in "${FILES[@]}"; do
  curl -fLsS --connect-timeout 10 --max-time 45 "$SOURCE/server/accounts/$name" -o "$STAGE/server/accounts/$name"
done
curl -fLsS --connect-timeout 10 --max-time 45 "$SOURCE/admin/selfhost/app.js" -o "$STAGE/app.js"
(cd "$STAGE" && "$PYTHON" -m unittest server.accounts.test_control server.accounts.test_control_password -q)
BACKUP=$(mktemp -d /opt/sovera-password-backup.XXXXXX)
chmod 700 "$BACKUP"
for name in "${FILES[@]}"; do
  if [ -f "$TARGET/server/accounts/$name" ]; then cp -a "$TARGET/server/accounts/$name" "$BACKUP/$name"; fi
done
cp -a "$WEB/app.js" "$BACKUP/app.js"
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
assert json.load(open(sys.argv[1])).get('ready') is True
PY
code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8092/sovera/control/password-login -H 'Host: admin.soverixnet.com' -H 'Origin: https://admin.soverixnet.com' -H 'Content-Type: application/json' --data '{"username":"deployment-probe","password":"not-a-real-password"}')
[ "$code" = 401 ] || { echo 'Password endpoint protection check failed'; exit 1; }
install -m 644 "$STAGE/app.js" "$WEB/app.js"
CHANGED=0
echo 'PASSWORD_LOGIN_INSTALLED'
echo "Backup: $BACKUP"
echo 'Set your own credentials now. Password typing is hidden.'
cd "$TARGET"
"$PYTHON" -m server.accounts.provision_password --single-owner
