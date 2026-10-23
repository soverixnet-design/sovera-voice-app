"""Root-only maintenance worker and independently verified SQLite backup copies."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import time

DATABASES={'account':'/var/lib/sovera-account/profiles.sqlite3','game':'/var/lib/sovera-greedy/game.sqlite3','wallet-journal':'/var/lib/sovera-greedy/game.sqlite3.wallet-journal'}

def file_hash(path):
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()

def verify_copy(path):
    with sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True) as db:
        if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise RuntimeError('Backup integrity check failed')
        tables={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        counts={name:db.execute('SELECT COUNT(*) FROM '+name).fetchone()[0] for name in ('account_profiles','account_wallet_ledger','account_control_audit') if name in tables}
        return counts

def backup(directory='/var/backups/sovera',databases=None):
    root=Path(directory);root.mkdir(mode=0o700,parents=True,exist_ok=True);os.chmod(root,0o700)
    stamp=time.strftime('%Y%m%dT%H%M%SZ',time.gmtime());dest=root/stamp
    if dest.exists():raise RuntimeError('Backup already exists for this second')
    dest.mkdir(mode=0o700);manifest={'created_at':int(time.time()),'verified':False,'files':{},'scope':'Online copies verified independently; cross-database restore requires coordinated recovery. No live database was replaced.'}
    try:
        for name,original in (databases or DATABASES).items():
            if not Path(original).is_file():continue
            target=dest/(name+'.sqlite3')
            with sqlite3.connect('file:'+str(original)+'?mode=ro',uri=True) as source,sqlite3.connect(target) as copy:source.backup(copy)
            os.chmod(target,0o600);counts=verify_copy(target)
            manifest['files'][name]={'bytes':target.stat().st_size,'sha256':file_hash(target),'counts':counts}
        if 'account' not in manifest['files']:raise RuntimeError('Account database backup required')
        manifest['verified']=True;(dest/'manifest.json').write_text(json.dumps(manifest,indent=2));os.chmod(dest/'manifest.json',0o600)
        # Delete only this worker's recognizable verified backup directories.
        for old in sorted(root.glob('????????T??????Z'))[:-14]:
            if old.is_dir() and not old.is_symlink() and (old/'manifest.json').is_file():
                try:
                    if json.loads((old/'manifest.json').read_text()).get('verified') is True:shutil.rmtree(old)
                except (OSError,ValueError):pass
        return manifest
    except Exception:
        shutil.rmtree(dest);raise

def record_backup(path,manifest):
    with sqlite3.connect(path,timeout=15) as db:
        db.execute('CREATE TABLE IF NOT EXISTS account_backup_status(created_at INTEGER PRIMARY KEY,payload TEXT NOT NULL)')
        db.execute('INSERT OR REPLACE INTO account_backup_status VALUES(?,?)',(manifest['created_at'],json.dumps(manifest)))
        db.execute('DELETE FROM account_backup_status WHERE created_at NOT IN (SELECT created_at FROM account_backup_status ORDER BY created_at DESC LIMIT 14)')

def tick(path):
    from .operations import Operations
    from .rewards import Rewards
    from .room_rewards import RoomRewards
    ops=Operations(path);ops.scheduled_tick();awards=Rewards(path).tick()+RoomRewards(path).tick()
    with ops.control.db() as db:
        db.execute('CREATE TABLE IF NOT EXISTS account_job_status(key TEXT PRIMARY KEY,last_run INTEGER NOT NULL,ok INTEGER NOT NULL,note TEXT NOT NULL)')
        db.execute("INSERT INTO account_job_status VALUES('maintenance',?,1,?) ON CONFLICT(key) DO UPDATE SET last_run=excluded.last_run,ok=1,note=excluded.note",(int(time.time()),f'{awards} reward claims applied'))
    return awards

def main():
    if os.geteuid()!=0:raise SystemExit('Run from the root server console')
    parser=argparse.ArgumentParser();parser.add_argument('--backup',action='store_true');args=parser.parse_args()
    with open('/run/sovera-maintenance.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if args.backup:
            result=backup();record_backup(DATABASES['account'],result);print('SOVERA_BACKUP_INTEGRITY_OK')
        else:tick(DATABASES['account']);print('SOVERA_MAINTENANCE_OK')
if __name__=='__main__':main()
