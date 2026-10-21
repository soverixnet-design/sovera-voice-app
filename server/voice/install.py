"""Update only the existing voice gateway; preserve credentials and roll back failures."""
import ast
import datetime
import pathlib
import shutil
import subprocess
import sys
import time
import urllib.request

commit = sys.argv[1]
if len(commit) != 40 or any(c not in '0123456789abcdef' for c in commit):
    raise SystemExit('STOP: Invalid source revision')
root = pathlib.Path('/opt/sovera-token')
app = root / 'app.py'
old = app.read_text()
settings = {}
for node in ast.parse(old).body:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in ('BASE', 'APIKEY'):
                settings[target.id] = ast.literal_eval(node.value)
if set(settings) != {'BASE', 'APIKEY'}:
    raise SystemExit('STOP: Existing public auth settings not found')
from livekit.protocol import models
from livekit import api
assert models.TrackSource.MICROPHONE == 2
api.UpdateParticipantRequest(room='check', identity='check', permission=models.ParticipantPermission(can_publish=False))
url = f'https://raw.githubusercontent.com/soverixnet-design/sovera-voice-app/{commit}/server/voice/app.py'
with urllib.request.urlopen(url, timeout=30) as fetched:
    source = fetched.read().decode()
for name, env in [('BASE','SOVERA_AUTH_URL'), ('APIKEY','SOVERA_PUBLIC_KEY')]:
    expected = f"{name} = os.environ['{env}']"
    assert source.count(expected) == 1
    source = source.replace(expected, f'{name} = {settings[name]!r}')
compile(source, str(app), 'exec')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
backup = root / ('app.py.before-seats-' + stamp)
shutil.copy2(app, backup)
backup.chmod(0o600)
try:
    app.write_text(source)
    app.chmod(0o600)
    subprocess.run(['systemctl','restart','sovera-token'], check=True)
    for attempt in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8090/sovera/health', timeout=2) as checked:
                import json
                if json.load(checked).get('seats') is True:
                    print('SEAT SERVER READY')
                    break
        except Exception:
            pass
        time.sleep(0.5)
    else:
        raise RuntimeError('Health check failed')
except Exception:
    shutil.copy2(backup, app)
    subprocess.run(['systemctl','restart','sovera-token'], check=False)
    raise SystemExit('UPDATE FAILED: previous gateway restored. Send this message only.')
