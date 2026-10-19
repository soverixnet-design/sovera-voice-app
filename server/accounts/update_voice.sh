#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'STOP: root console required'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
ROOT=/opt/sovera-account
UNIT=/etc/systemd/system/sovera-account.service
SECRETS=/root/sovera-livekit-secrets.env
[ -s "$SECRETS" ] && [ -f "$ROOT/server/accounts/app.py" ] && [ -s /var/lib/sovera-account/profiles.sqlite3 ] || { echo 'STOP: existing account service or voice configuration missing'; exit 1; }
"$PYTHON" -c 'from livekit import api; import jwt'
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/6eb6e23026fdf93325e9409c9443bebcb7f22fb8
STAGING=$(mktemp -d /opt/sovera-voice-update.XXXXXX)
BACKUP=$(mktemp -d /opt/sovera-voice-backup.XXXXXX)
chmod 700 "$STAGING" "$BACKUP"
CHANGED=0
cleanup(){
 code=$?
 if [ "$code" != 0 ] && [ "$CHANGED" = 1 ]; then
  cp -a "$BACKUP/accounts/." "$ROOT/server/accounts/"
  cp -a "$BACKUP/account.service" "$UNIT"
  if [ -f "$BACKUP/voice-app.py" ]; then cp -a "$BACKUP/voice-app.py" "$ROOT/server/voice/app.py"; fi
  systemctl daemon-reload
  systemctl restart sovera-account || true
  echo 'UPDATE_FAILED: previous account service restored'
 fi
 rm -rf "$STAGING"
}
trap cleanup EXIT
mkdir -p "$STAGING/server/accounts" "$STAGING/server/voice"
for file in app.py rooms.py duel.py global_games.py food_wheel.py voice.py test_accounts.py test_voice.py test_duel.py test_global_games.py test_food_wheel.py; do
 curl --fail --silent --show-error --connect-timeout 10 --max-time 45 "$SOURCE/server/accounts/$file" -o "$STAGING/server/accounts/$file"
done
for file in app.py test_seats.py test_firebase_auth.py; do
 curl --fail --silent --show-error --connect-timeout 10 --max-time 45 "$SOURCE/server/voice/$file" -o "$STAGING/server/voice/$file"
done
(cd "$STAGING" && "$PYTHON" -m unittest server.accounts.test_accounts server.accounts.test_voice server.accounts.test_duel server.accounts.test_global_games server.accounts.test_food_wheel server.voice.test_seats server.voice.test_firebase_auth -q)
cp -a "$ROOT/server/accounts" "$BACKUP/accounts"
cp -a "$UNIT" "$BACKUP/account.service"
if [ -f "$ROOT/server/voice/app.py" ]; then cp -a "$ROOT/server/voice/app.py" "$BACKUP/voice-app.py"; fi
"$PYTHON" - "$BACKUP/profiles.sqlite3" <<'PY'
import sqlite3,sys,os
source=sqlite3.connect('file:/var/lib/sovera-account/profiles.sqlite3?mode=ro',uri=True)
dest=sqlite3.connect(sys.argv[1])
try: source.backup(dest)
finally: dest.close();source.close()
os.chmod(sys.argv[1],0o600)
PY
"$PYTHON" - "$UNIT" "$STAGING/account.service" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
assert '[Service]' in s and 'server.accounts.app:create' in s
lines=[x for x in s.splitlines() if not x.startswith(('Environment=SOVERA_ACCOUNT_VOICE=','Environment=SOVERA_VOICE_ROOM_PREFIX='))]
s='\n'.join(lines)+'\n'
if 'EnvironmentFile=/root/sovera-livekit-secrets.env' not in s:
 s=s.replace('[Service]','[Service]\nEnvironmentFile=/root/sovera-livekit-secrets.env',1)
s=s.replace('[Service]','[Service]\nEnvironment=SOVERA_ACCOUNT_VOICE=1\nEnvironment=SOVERA_VOICE_ROOM_PREFIX=fb-',1)
Path(sys.argv[2]).write_text(s)
PY
CHANGED=1
mkdir -p "$ROOT/server/voice"
for file in app.py rooms.py duel.py global_games.py food_wheel.py voice.py test_accounts.py test_voice.py test_duel.py test_global_games.py test_food_wheel.py; do install -m 644 "$STAGING/server/accounts/$file" "$ROOT/server/accounts/$file"; done
install -m 644 "$STAGING/server/voice/app.py" "$ROOT/server/voice/app.py"
install -m 644 "$STAGING/account.service" "$UNIT"
systemctl daemon-reload
systemctl restart sovera-account
curl --fail --silent --show-error --retry 8 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8092/sovera/account/health -o "$STAGING/health.json"
"$PYTHON" - "$STAGING/health.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))
assert all(h.get(k) is True for k in ('ready','profiles','rooms','chat','voice','room_effects','free_duel','global_color_game','food_wheel_preview'))
assert h.get('wallet') is False and h.get('games') is False
PY
CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 -H 'Content-Type: application/json' -d '{"room_id":"00000000-0000-0000-0000-000000000000"}' http://127.0.0.1:8092/sovera/account/voice)
[ "$CODE" = 401 ] || { echo 'STOP: voice authentication protection failed'; exit 1; }
for route in /sovera/account/games/colors /sovera/account/wheel/state /sovera/account/rooms/00000000-0000-0000-0000-000000000000/duel; do
 CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "http://127.0.0.1:8092$route")
 [ "$CODE" = 401 ] || { echo "STOP: unauthenticated game endpoint available: $route"; exit 1; }
done
echo FIREBASE_VOICE_AND_FOOD_WHEEL_PREVIEW_API_READY
echo "Backup: $BACKUP"
