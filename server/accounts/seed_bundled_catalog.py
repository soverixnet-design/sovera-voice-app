"""Import bundled artwork once; keep all owner edits, grants and wallet history."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import time
import uuid
from .catalog import Catalog,ItemInput

NAMESPACE=uuid.UUID('d162f02b-57a1-47fa-bca1-34c13eec199d')
def item_id(item):
    key=str(item['builtin_slide']) if 'builtin_slide' in item else item['path']
    return str(uuid.uuid5(NAMESPACE,item['kind']+':'+key))
def seed(database,root):
    catalog=Catalog(database)
    rows=json.loads(Path(__file__).with_name('bundled_catalog.json').read_text())
    with catalog.control.db() as db:
        owners=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
        if len(owners)!=1:raise ValueError('Exactly one assigned owner required')
        owner=owners[0]['uid']
    added=0
    for position,item in enumerate(rows):
        key=item_id(item)
        with catalog.control.db() as db:
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
        path=Path(root)/item['path']
        image=catalog.upload(owner,path.read_bytes())
        # Acquire the same write lock as the admin editor; a retry never replaces edits.
        with catalog.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
            catalog.manage(db,owner)
            db.execute('INSERT INTO account_catalog VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                (key,item['kind'],item['title'],image['id'],item['price'],1,position,
                 item.get('avatar_scale',.46),item.get('avatar_x',.5),item.get('avatar_y',.5),int(time.time())))
            if 'builtin_slide' in item:
                db.execute('INSERT OR IGNORE INTO account_builtin_catalog VALUES(?,?,?,?)',
                    (key,image['id'],item['builtin_slide'],item['subtitle']))
            catalog.control.audit(db,owner,'catalog.import_builtin',key,{'path':item['path']})
            added+=1
    return {'added':added,'total_bundled':len(rows)}
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',default='/var/lib/sovera-account/profiles.sqlite3')
    parser.add_argument('--root',required=True)
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Run in the root server console')
    if not Path(args.database).is_file():parser.error('Existing database required')
    backup=args.database+'.before-catalog-'+str(time.time_ns())
    source=sqlite3.connect('file:'+args.database+'?mode=ro',uri=True)
    target=sqlite3.connect(backup)
    try:source.backup(target)
    finally:target.close();source.close()
    os.chmod(backup,0o600)
    print(json.dumps(seed(args.database,args.root)))
    print('BUNDLED_CATALOG_READY')
    print('Backup:',backup)
if __name__=='__main__':main()
