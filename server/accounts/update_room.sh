#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Run in the root server SSH session'; exit 1; }
SOURCE=https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/__ROOM_SOURCE_COMMIT__
[[ "$SOURCE" =~ /[a-f0-9]{40}$ ]] || { echo 'Use the pinned updater attached to the release'; exit 1; }
exec 9>/run/sovera-community-update.lock
flock -n 9 || { echo 'Another account update is running'; exit 1; }
PYTHON=/opt/sovera-food-staging/.venv/bin/python
NODE=/opt/sovera-greedy/node22/bin/node
TARGET=/opt/sovera-account
GAME=/opt/sovera-greedy/live
DATABASE=/var/lib/sovera-account/profiles.sqlite3
systemctl is-active --quiet sovera-account
systemctl is-active --quiet sovera-greedy
[ -x "$PYTHON" ] && [ -x "$NODE" ] && [ -s "$DATABASE" ] && [ -f "$GAME/src/engine.js" ] || exit 1
STAGE=$(mktemp -d /opt/sovera-room-stage.XXXXXX)
chmod 755 "$STAGE"
BACKUP=
CHANGED=0
FILES=(members.py test_members.py test_legacy_wallet.py import_legacy_wallet.py test_auto_wallet.py messaging.py test_messaging.py control.py community.py room_photos.py test_room_photos.py broadcasts.py test_broadcasts.py greedy_wallet.py catalog.py app.py wallet.py rooms.py voice.py room_controls.py test_room_controls.py profile_media.py seed_gifts.py test_profile_media.py test_wallet.py test_catalog.py)
GAMEFILES=(start.js limits.js selftest.js)
ADMIN=/opt/livekit/caddy_data/sovera-control
[ -d "$ADMIN" ] || { echo "Existing admin installation required"; exit 1; }
ADMINFILES=(app.js index.html style.css)
cleanup(){
  result=$?
  if [ "$result" != 0 ] && [ "$CHANGED" = 1 ]; then
    for name in "${FILES[@]}"; do
      if [ -f "$BACKUP/account/$name" ]; then install -m 644 "$BACKUP/account/$name" "$TARGET/server/accounts/$name"; else rm -f "$TARGET/server/accounts/$name"; fi
    done
    for name in "${GAMEFILES[@]}"; do
      if [ -f "$BACKUP/game/$name" ]; then install -m 644 "$BACKUP/game/$name" "$GAME/src/$name"; else rm -f "$GAME/src/$name"; fi
    done
    if [ -f "$BACKUP/gateway.py" ]; then install -m 644 "$BACKUP/gateway.py" "$TARGET/server/voice/app.py"; fi
    for name in "${ADMINFILES[@]}"; do
      if [ -f "$BACKUP/admin/$name" ]; then install -m 644 "$BACKUP/admin/$name" "$ADMIN/$name"; fi
    done
    if [ -f "$BACKUP/greedy-account.env" ]; then install -m 600 "$BACKUP/greedy-account.env" /etc/sovera-greedy-account.env; fi
    systemctl restart sovera-account || true
    systemctl restart sovera-greedy || true
    echo 'Previous code restored; wallet and game transactions preserved.'
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
cp -a "$TARGET/server" "$STAGE/server"
mkdir "$STAGE/game" "$STAGE/admin"
for name in "${ADMINFILES[@]}"; do
  curl -fLsS --retry 3 --connect-timeout 10 --max-time 60 "$SOURCE/admin/selfhost/$name" -o "$STAGE/admin/$name"
done
"$NODE" --check "$STAGE/admin/app.js"
cp -a "$GAME/src" "$STAGE/game/src"
ln -s "$GAME/node_modules" "$STAGE/game/node_modules"
for name in "${FILES[@]}"; do
  curl -fLsS --retry 3 --connect-timeout 10 --max-time 60 "$SOURCE/server/accounts/$name" -o "$STAGE/server/accounts/$name"
done
for name in "${GAMEFILES[@]}"; do
  curl -fLsS --retry 3 --connect-timeout 10 --max-time 60 "$SOURCE/server/greedy/$name" -o "$STAGE/game/src/$name"
  "$NODE" --check "$STAGE/game/src/$name"
done
(cd "$STAGE" && "$PYTHON" -m unittest server.accounts.test_members server.accounts.test_auto_wallet server.accounts.test_legacy_wallet server.accounts.test_messaging server.accounts.test_control server.accounts.test_room_photos server.accounts.test_broadcasts server.accounts.test_wallet server.accounts.test_catalog server.accounts.test_accounts server.accounts.test_profile_media server.accounts.test_room_controls server.accounts.test_voice server.accounts.test_greedy_wallet server.accounts.test_greedy_access -q)
curl -fLsS --retry 3 --connect-timeout 10 --max-time 60 "$SOURCE/server/voice/app.py" -o "$STAGE/server/voice/app.py"
(cd "$STAGE" && "$PYTHON" -m unittest server.accounts.test_room_controls server.accounts.test_voice -q)
echo 'Testing a shared round above one million using isolated test balances...'
"$NODE" "$STAGE/game/src/selftest.js" "$STAGE/game" --large-bet
BACKUP=$(mktemp -d /opt/sovera-room-backup.XXXXXX)
chmod 700 "$BACKUP"
mkdir "$BACKUP/account" "$BACKUP/game" "$BACKUP/admin"
for name in "${ADMINFILES[@]}"; do cp -a "$ADMIN/$name" "$BACKUP/admin/$name"; done
for name in "${FILES[@]}"; do
  if [ -f "$TARGET/server/accounts/$name" ]; then cp -a "$TARGET/server/accounts/$name" "$BACKUP/account/$name"; fi
done
for name in "${GAMEFILES[@]}"; do
  if [ -f "$GAME/src/$name" ]; then cp -a "$GAME/src/$name" "$BACKUP/game/$name"; fi
done
"$PYTHON" - "$BACKUP" <<'PY'
import os,sqlite3,sys
from pathlib import Path
for original,name in [
('/var/lib/sovera-account/profiles.sqlite3','account.sqlite3'),
('/var/lib/sovera-greedy/game.sqlite3','game.sqlite3'),
('/var/lib/sovera-greedy/game.sqlite3.wallet-journal','wallet-journal.sqlite3')]:
    if not Path(original).is_file():continue
    dest=str(Path(sys.argv[1])/name)
    source=sqlite3.connect('file:'+original+'?mode=ro',uri=True)
    target=sqlite3.connect(dest)
    try:source.backup(target)
    finally:target.close();source.close()
    os.chmod(dest,0o600)
PY
cp -a "$TARGET/server/voice/app.py" "$BACKUP/gateway.py"
cp -a /etc/sovera-greedy-account.env "$BACKUP/greedy-account.env"
CHANGED=1
"$PYTHON" - <<'PYENV'
from pathlib import Path
p=Path('/etc/sovera-greedy-account.env')
lines=[line for line in p.read_text().splitlines() if not line.startswith('SOVERA_AUTO_WALLETS=')]
p.write_text('\n'.join(lines+['SOVERA_AUTO_WALLETS=1'])+'\n')
p.chmod(0o600)
PYENV
for name in "${ADMINFILES[@]}"; do install -m 644 "$STAGE/admin/$name" "$ADMIN/$name"; done
install -m 644 "$STAGE/server/voice/app.py" "$TARGET/server/voice/app.py"
for name in "${FILES[@]}"; do install -m 644 "$STAGE/server/accounts/$name" "$TARGET/server/accounts/$name"; done
for name in "${GAMEFILES[@]}"; do install -m 644 "$STAGE/game/src/$name" "$GAME/src/$name"; done
(cd "$TARGET" && "$PYTHON" -m server.accounts.seed_gifts --database "$DATABASE")
systemctl restart sovera-account
curl -fSs --retry 10 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8092/sovera/account/health -o "$STAGE/health.json"
"$PYTHON" - "$STAGE/health.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('ready') is True
PY
systemctl restart sovera-greedy
curl -fSs --retry 10 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:8080/health -o "$STAGE/game-health.json"
"$PYTHON" - "$STAGE/game-health.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('walletMode')=='http'
PY
CHANGED=0
echo 'MEMBER_IDS_SOCIAL_AGENCY_READY'
echo "Backup: $BACKUP"
echo 'Four animated gifts seeded once. Owner edits remain in the admin catalog.'
echo 'Diamond exchange: 100 Diamonds = 70 Coins.'
echo 'Former one-million round cap removed. Wallet balance and exact arithmetic checks remain.'
