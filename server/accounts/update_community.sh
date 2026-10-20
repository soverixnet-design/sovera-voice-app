#!/usr/bin/env bash
# Install the reviewed community + wallet bridge without resetting user data.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Root server console required'; exit 1; }
exec 9>/run/sovera-community-update.lock
flock -n 9 || { echo 'Another account update is running'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
TARGET=/opt/sovera-account
DATABASE=/var/lib/sovera-account/profiles.sqlite3
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/e77c320370279a86c0af0b0eac646911e1592aee
[ -x "$PYTHON" ] && [ -f "$TARGET/server/accounts/app.py" ] && [ -s "$DATABASE" ] || { echo 'Existing account server is required'; exit 1; }
systemctl is-active --quiet sovera-account || { echo 'Account service is not active'; exit 1; }
FILES=(server/accounts/app.py server/accounts/rooms.py server/accounts/wallet.py
 server/accounts/greedy_wallet.py server/accounts/greedy_access.py
 server/accounts/community.py server/accounts/duel.py server/accounts/global_games.py
 server/accounts/food_wheel.py server/accounts/voice.py server/voice/app.py
 server/accounts/test_accounts.py server/accounts/test_wallet.py
 server/accounts/test_greedy_wallet.py server/accounts/test_greedy_access.py
 server/accounts/test_community.py server/accounts/test_duel.py
 server/accounts/test_global_games.py server/accounts/test_food_wheel.py)
STAGING=$(mktemp -d /opt/sovera-community-stage.XXXXXX)
BACKUP=
CHANGED=0
cleanup(){
  code=$?
  if [ "$code" != 0 ] && [ "$CHANGED" = 1 ]; then
    for file in "${FILES[@]}"; do
      if [ -f "$BACKUP/$file" ]; then
        install -m 644 "$BACKUP/$file" "$TARGET/$file"
      else
        rm -f "$TARGET/$file"
      fi
    done
    systemctl restart sovera-account || true
    echo 'Update failed; previous server code restored. New user data was not overwritten.'
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
for file in "${FILES[@]}"; do
  mkdir -p "$STAGING/$(dirname "$file")"
  curl --fail --silent --show-error --connect-timeout 10 --max-time 45 "$SOURCE/$file" -o "$STAGING/$file"
done
(cd "$STAGING" && "$PYTHON" -m unittest server.accounts.test_accounts) >/dev/null
(cd "$STAGING" && "$PYTHON" -m unittest server.accounts.test_community \
 server.accounts.test_wallet server.accounts.test_greedy_wallet \
 server.accounts.test_greedy_access server.accounts.test_duel \
 server.accounts.test_global_games server.accounts.test_food_wheel -q)
BACKUP=$(mktemp -d /opt/sovera-community-backup.XXXXXX)
chmod 700 "$BACKUP"
cp -a "$TARGET/server" "$BACKUP/server"
"$PYTHON" - "$DATABASE" "$BACKUP/profiles.sqlite3" <<'PY'
import os,sqlite3,sys
source=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
destination=sqlite3.connect(sys.argv[2])
try:
    source.backup(destination)
finally:
    destination.close()
    source.close()
os.chmod(sys.argv[2],0o600)
PY
CHANGED=1
for file in "${FILES[@]}"; do
  install -d -m 755 "$TARGET/$(dirname "$file")"
  install -m 644 "$STAGING/$file" "$TARGET/$file"
done
systemctl restart sovera-account
curl --fail --silent --show-error --retry 8 --retry-connrefused --retry-delay 1 --max-time 5 \
  http://127.0.0.1:8092/sovera/account/health -o "$STAGING/health.json"
"$PYTHON" - "$STAGING/health.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))
assert h.get('ready') is True and h.get('rooms') is True and h.get('chat') is True
PY
for path in community/moments community/support staff; do
  code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "http://127.0.0.1:8092/sovera/account/$path")
  [ "$code" = 401 ] || { echo 'Account access protection check failed'; exit 1; }
done
echo 'COMMUNITY_SERVER_READY'
echo 'Wallet cutover and real-device audio still require separate verification.'
echo "Backup: $BACKUP"
