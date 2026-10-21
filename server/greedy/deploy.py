"""Root deployment of the uploaded Greedy game against the existing Sovera ledger."""
import argparse,fcntl,hashlib,hmac,json,os,re,secrets,shutil,sqlite3,subprocess,sys,tempfile,time
from pathlib import Path
from urllib.request import Request,urlopen
ROOT=Path('/opt/sovera-greedy')
ORIGINAL=ROOT/'app/greedy-server'
LIVE=ROOT/'live'
NODE=ROOT/'node22/bin/node'
ACCOUNT=Path('/opt/sovera-account')
DB=Path('/var/lib/sovera-account/profiles.sqlite3')
PYTHON='/opt/sovera-food-staging/.venv/bin/python'
CADDY=Path('/opt/livekit/caddy.yaml')
CONTAINER='livekit-caddy-1'
SERVICE=Path('/etc/systemd/system/sovera-greedy.service')
DROP=Path('/etc/systemd/system/sovera-account.service.d/greedy.conf')
GAME_ENV=Path('/etc/sovera-greedy.env')
ACCOUNT_ENV=Path('/etc/sovera-greedy-account.env')
def run(args,**kwargs):
    return subprocess.run([str(x) for x in args],check=True,**kwargs)
def quiet(args):return run(args,stdout=subprocess.PIPE,text=True).stdout
def write(path,data,mode=0o600):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(data);path.chmod(mode)
def fetch(url):return urlopen(url,timeout=45).read()
def get(url):
    with urlopen(url,timeout=8) as response:return json.load(response)
def wait(url,check):
    for i in range(20):
        try:
            value=get(url)
            if check(value):return value
        except Exception:pass
        time.sleep(.5)
    raise RuntimeError('Service readiness check failed: '+url)
def backup_db(path,target):
    a=sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True);b=sqlite3.connect(target)
    try:a.backup(b)
    finally:b.close();a.close()
    Path(target).chmod(0o600)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True)
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Root SSH session required')
    if not re.fullmatch(r'https://raw\.githubusercontent\.com/soverixnet-design/sovera-voice-app/[a-f0-9]{40}',args.source):parser.error('Pinned source required')
    lock=open('/run/sovera-community-update.lock','w')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    for path in [NODE,ORIGINAL/'src/server.js',ORIGINAL/'src/engine.js',ORIGINAL/'node_modules',ACCOUNT/'server/accounts/greedy_wallet.py',DB,CADDY]:
        if not path.exists():raise RuntimeError('Missing existing installation: '+str(path))
    if subprocess.run(['systemctl','is-active','--quiet','sovera-greedy']).returncode==0:
        raise RuntimeError('Greedy is already running; inspect the active game before replacing it')
    if Path('/var/lib/sovera-greedy/game.sqlite3').exists():raise RuntimeError('Existing production game history requires reconciliation before first activation')
    if LIVE.exists():raise RuntimeError('A prepared live game already exists; preserve it and inspect before retrying')
    run(['systemctl','is-active','--quiet','sovera-account'])
    major=int(quiet([NODE,'-p','process.versions.node.split(".")[0]']).strip())
    if major<22:raise RuntimeError('Node 22 or later required')
    if not (ROOT/'app/greedy-game/index.html').is_file():raise RuntimeError('Original uploaded game artwork missing')
    with sqlite3.connect('file:'+str(DB)+'?mode=ro',uri=True) as db:
        owners=db.execute("SELECT s.uid FROM account_staff s JOIN account_wallet_links w ON w.firebase_uid=s.uid WHERE s.role='owner' AND w.status='active' AND w.verified_at>0").fetchall()
        if len(owners)!=1:raise RuntimeError('Exactly one owner with a verified wallet is required')
        owner=owners[0][0]
    stage=Path(tempfile.mkdtemp(prefix='sovera-greedy-stage-',dir='/opt'))
    stage.chmod(0o755)
    backup=Path(tempfile.mkdtemp(prefix='sovera-greedy-backup-',dir='/opt'));backup.chmod(0o700)
    changed=False;original_caddy=CADDY.read_bytes();saved={}
    try:
        for path in [SERVICE,DROP,GAME_ENV,ACCOUNT_ENV]:
            saved[path]=path.read_bytes() if path.exists() else None
            if path.exists():shutil.copy2(path,backup/path.name)
        (backup/'caddy.yaml').write_bytes(original_caddy)
        backup_db(DB,backup/'profiles.sqlite3')
        # Keep the previous local/mock game and database intact.
        shutil.copytree(ORIGINAL/'src',stage/'src')
        os.symlink(ORIGINAL/'node_modules',stage/'node_modules',target_is_directory=True)
        for name in ['wallet.js','start.js','limits.js','selftest.js']:
            (stage/'src'/name).write_bytes(fetch(args.source+'/server/greedy/'+name))
        server=stage/'src/server.js'
        text=server.read_text()
        old="server.listen(cfg.port, '0.0.0.0'"
        if old not in text:raise RuntimeError('Original server listen statement changed; review before deployment')
        server.write_text(text.replace(old,"server.listen(cfg.port, '127.0.0.1'",1))
        for path in (stage/'src').glob('*.js'):run([NODE,'--check',path])
        print('Testing isolated wallets, crash recovery and an original game round...',flush=True)
        run([NODE,stage/'src/selftest.js',stage],timeout=90)
        run([PYTHON,'-m','unittest','server.accounts.test_greedy_wallet','server.accounts.test_greedy_access','server.accounts.test_wallet','-q'],cwd=ACCOUNT,timeout=90)
        mount=json.loads(quiet(['docker','inspect',CONTAINER,'--format','{{json .Mounts}}']))
        mapping={m['Destination']:m['Source'] for m in mount if m['Type']=='bind'}
        if mapping.get('/etc/caddy.yaml')!=str(CADDY):raise RuntimeError('Unexpected Caddy bind mount')
        config=json.loads(quiet(['docker','exec',CONTAINER,'caddy','adapt','--config','/etc/caddy.yaml','--adapter','yaml']))
        servers=config['apps']['http']['servers']
        candidates=[s for s in servers.values() if '127.0.0.1:7882' in s.get('listen',[])]
        if len(candidates)!=1:raise RuntimeError('Original voice HTTP router not found')
        routes=candidates[0]['routes']
        if any('/greedy' in json.dumps(r) for r in routes):raise RuntimeError('Existing Greedy proxy route requires review')
        routes[:0]=[
          {'match':[{'path':['/sovera/account/internal/greedy-wallet/*']}],'handle':[{'handler':'static_response','status_code':404}],'terminal':True},
          {'match':[{'path':['/greedy']}],'handle':[{'handler':'static_response','status_code':308,'headers':{'Location':['/greedy/']}}],'terminal':True},
          {'match':[{'path':['/greedy/*']}],'handle':[{'handler':'rewrite','strip_path_prefix':'/greedy'},{'handler':'reverse_proxy','upstreams':[{'dial':'127.0.0.1:8080'}]}],'terminal':True}]
        candidate=stage/'caddy.json';candidate.write_text(json.dumps(config))
        remote='/tmp/sovera-greedy-candidate.json'
        run(['docker','cp',candidate,CONTAINER+':'+remote],stdout=subprocess.DEVNULL)
        run(['docker','exec',CONTAINER,'caddy','validate','--config',remote,'--adapter','yaml'])
        jwt=secrets.token_hex(32);wallet=secrets.token_hex(32)
        account_env='SOVERA_GREEDY_ENABLED=1\nSOVERA_GREEDY_WALLET_VERIFIED=1\nSOVERA_GREEDY_JWT_SECRET='+jwt+'\nSOVERA_GREEDY_WALLET_SECRET='+wallet+'\nSOVERA_GREEDY_PUBLIC_URL=https://voice.soverixnet.com/greedy/\n'
        game_env='PORT=8080\nDB_FILE=/var/lib/sovera-greedy/game.sqlite3\nDEMO_AUTH=0\nLOCAL_START_BALANCE=0\nWALLET_MODE=http\nWALLET_URL=http://127.0.0.1:8092/sovera/account/internal/greedy-wallet\nGAME_JWT_SECRET='+jwt+'\nWALLET_SECRET='+wallet+'\nCLIENT_DIR='+str(ROOT/'app/greedy-game')+'\nCHIPS=1000,10000,100000,1000000\nMIN_BET=1000\nMAX_BET_PER_ROUND=1000000\n'
        changed=True
        LIVE.mkdir(mode=0o755);shutil.copytree(stage/'src',LIVE/'src')
        for f in (LIVE/'src').glob('*'):
            if f.is_file():f.chmod(0o644)
        os.symlink(ORIGINAL/'node_modules',LIVE/'node_modules',target_is_directory=True)
        write(GAME_ENV,game_env);write(ACCOUNT_ENV,account_env)
        write(DROP,'[Service]\nEnvironmentFile=/etc/sovera-greedy-account.env\n',0o644)
        write(SERVICE,'[Unit]\nDescription=Sovera Greedy verified coin game\nAfter=network-online.target sovera-account.service\nWants=network-online.target\n[Service]\nType=simple\nDynamicUser=yes\nStateDirectory=sovera-greedy\nStateDirectoryMode=0700\nWorkingDirectory='+str(LIVE)+'\nEnvironmentFile=/etc/sovera-greedy.env\nExecStart='+str(NODE)+' '+str(LIVE/'src/start.js')+'\nRestart=on-failure\nRestartSec=5\nUMask=0077\nNoNewPrivileges=yes\nProtectSystem=strict\nProtectHome=yes\nPrivateTmp=yes\n[Install]\nWantedBy=multi-user.target\n',0o644)
        run(['systemd-analyze','verify',SERVICE])
        run(['systemctl','daemon-reload']);run(['systemctl','restart','sovera-account'])
        wait('http://127.0.0.1:8092/sovera/account/health',lambda h:h.get('ready') is True)
        # Verify the real wallet READ ONLY. All earlier money tests were isolated.
        body=json.dumps({'userId':owner},separators=(',',':')).encode()
        stamp=str(int(time.time()*1000));signature=hmac.new(wallet.encode(),stamp.encode()+b'.'+body,hashlib.sha256).hexdigest()
        request=Request('http://127.0.0.1:8092/sovera/account/internal/greedy-wallet/balance',data=body,headers={'Content-Type':'application/json','X-Greedy-Timestamp':stamp,'X-Greedy-Signature':signature})
        with urlopen(request,timeout=10) as response:balance=json.load(response)
        if balance.get('ok') is not True:raise RuntimeError('Existing wallet read verification failed')
        run(['systemctl','start','sovera-greedy'])
        wait('http://127.0.0.1:8080/health',lambda h:h.get('ok') is True and h.get('walletMode')=='http')
        # Write in place: Docker bind mounts must retain the original inode.
        CADDY.write_text(candidate.read_text())
        run(['docker','exec',CONTAINER,'caddy','reload','--config','/etc/caddy.yaml','--adapter','yaml'])
        wait('https://voice.soverixnet.com/greedy/health',lambda h:h.get('walletMode')=='http')
        run(['systemctl','enable','sovera-greedy'],stdout=subprocess.DEVNULL)
        print('GREEDY_SERVER_READY')
        print('Existing owner balance preserved:',balance['balance'])
        print('Backup:',backup)
        print('Game URL: https://voice.soverixnet.com/greedy/')
    except Exception:
        if changed:
            subprocess.run(['systemctl','stop','sovera-greedy'])
            CADDY.write_bytes(original_caddy)
            subprocess.run(['docker','exec',CONTAINER,'caddy','reload','--config','/etc/caddy.yaml','--adapter','yaml'])
            for path,data in saved.items():
                if data is None:path.unlink(missing_ok=True)
                else:path.write_bytes(data);path.chmod(0o600 if path in (GAME_ENV,ACCOUNT_ENV) else 0o644)
            subprocess.run(['systemctl','daemon-reload']);subprocess.run(['systemctl','restart','sovera-account'])
            # Retain diagnostic code and every database, never overwrite live money.
            print('Game activation failed; prior account/proxy settings restored. Money databases were preserved.')
        print('Backup:',backup)
        raise
    finally:shutil.rmtree(stage,ignore_errors=True)
if __name__=='__main__':
    try:main()
    except Exception as error:print('STOP:',error,file=sys.stderr);sys.exit(1)
