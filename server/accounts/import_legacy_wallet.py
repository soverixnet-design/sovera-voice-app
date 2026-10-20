"""Root-only, audited import of a frozen legacy wallet; never an HTTP endpoint."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import time
import uuid

PROJECT='rfrmcmeyamndghtiheci'
LIMIT=9007199254740991
class ImportRejected(ValueError):pass

def reject(message):raise ImportRejected(message)
def integer(value,*,signed=False):
    if isinstance(value,bool):reject('Boolean is not a wallet amount')
    if isinstance(value,int):result=value
    elif isinstance(value,str) and re.fullmatch(r'-?(0|[1-9][0-9]*)' if signed else r'0|[1-9][0-9]*',value):result=int(value)
    else:reject('Invalid wallet amount')
    if abs(result)>LIMIT or (not signed and result<0):reject('Wallet amount outside supported range')
    return result
def validate(manifest):
    if not isinstance(manifest,dict) or set(manifest)!={'payload','sha256'}:reject('Invalid snapshot envelope')
    raw=manifest['payload']
    if not isinstance(raw,str) or len(raw.encode())>4*1024*1024:reject('Invalid snapshot size')
    digest=hashlib.sha256(raw.encode()).hexdigest()
    if digest!=manifest['sha256']:reject('Snapshot checksum does not match')
    try:data=json.loads(raw)
    except (TypeError,ValueError):reject('Invalid snapshot JSON')
    if data.get('version')!=1 or data.get('source_project')!=PROJECT or data.get('wallet_status')!='frozen':reject('A frozen original-project snapshot is required')
    try:
        legacy=str(uuid.UUID(data['legacy_user_id']))
        snapshot_id=str(uuid.UUID(data['snapshot_id']))
        frozen=datetime.fromisoformat(data['frozen_at'].replace('Z','+00:00'))
    except (ValueError,TypeError,KeyError,AttributeError):reject('Invalid snapshot identity or cutoff')
    if frozen.tzinfo is None or frozen.timestamp()>time.time()+300:reject('Invalid snapshot cutoff')
    public_id=data.get('public_id')
    if not isinstance(public_id,str) or not re.fullmatch(r'[0-9]{4,20}',public_id):reject('Verified legacy public ID required')
    coins,diamonds=integer(data.get('coins')),integer(data.get('diamonds'))
    rows=data.get('entries')
    if not isinstance(rows,list) or len(rows)>10000:reject('Invalid ledger history')
    seen=set();entries=[]
    for row in rows:
        if not isinstance(row,dict):reject('Invalid ledger entry')
        try:
            entry_id=str(uuid.UUID(row['id']))
            owner=str(uuid.UUID(row['user_id']))
            created=datetime.fromisoformat(row['created_at'].replace('Z','+00:00'))
        except (ValueError,TypeError,KeyError,AttributeError):reject('Invalid ledger identity or timestamp')
        if owner!=legacy or entry_id in seen:reject('Foreign or duplicate ledger entry')
        if created.tzinfo is None or created.timestamp()<=0 or created>frozen:reject('Entry is outside frozen snapshot')
        seen.add(entry_id)
        coin=integer(row.get('coin_delta'),signed=True);diamond=integer(row.get('diamond_delta'),signed=True)
        entries.append({'reference':'legacy:'+PROJECT+':'+entry_id,'coin_delta':coin,
          'diamond_delta':diamond,'created_at':int(created.timestamp())})
    if sum(e['coin_delta'] for e in entries)!=coins or sum(e['diamond_delta'] for e in entries)!=diamonds:reject('Ledger totals do not match the frozen balance')
    return {'source_ref':'supabase:'+PROJECT+':'+legacy,'snapshot_id':snapshot_id,
      'snapshot_hash':digest,'public_id':public_id,'coins':coins,'diamonds':diamonds,
      'entries':entries,'proof':raw}

def import_wallet(database,manifest,*,target_uid=None,owner=False,apply=False):
    plan=validate(manifest)
    if not Path(database).is_file():reject('Existing server database required')
    db=sqlite3.connect(str(database),timeout=20)
    db.row_factory=sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    try:
        db.execute('BEGIN IMMEDIATE')
        tables={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {'account_profiles','account_staff','account_wallet_links','account_wallet_ledger','account_wallet_imports'}<=tables:reject('Install the wallet migration update first')
        if owner:
            owners=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
            if len(owners)!=1:reject('Exactly one console-assigned owner is required')
            if target_uid and target_uid!=owners[0]['uid']:reject('Owner and selected UID differ')
            target_uid=owners[0]['uid']
        if not target_uid or not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(target_uid,)).fetchone():reject('Select the confirmed existing Firebase profile')
        prior=db.execute('SELECT * FROM account_wallet_imports WHERE source_ref=? OR firebase_uid=? OR public_id=? OR snapshot_id=?',(plan['source_ref'],target_uid,plan['public_id'],plan['snapshot_id'])).fetchall()
        link=db.execute('SELECT * FROM account_wallet_links WHERE firebase_uid=? OR source_ref=?',(target_uid,plan['source_ref'])).fetchall()
        def totals():
            values=db.execute('SELECT COALESCE(SUM(coin_delta),0),COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(target_uid,)).fetchone()
            if min(values)<0 or max(values)>LIMIT:reject('Local wallet reconciliation required')
            return tuple(values)
        if prior:
            if len(prior)!=1:reject('Conflicting source, public ID or Firebase mapping')
            row=prior[0]
            if (row['source_ref'],row['firebase_uid'],row['public_id'],row['snapshot_id'],row['snapshot_hash'])!=(plan['source_ref'],target_uid,plan['public_id'],plan['snapshot_id'],plan['snapshot_hash']):reject('A different wallet mapping or snapshot already exists')
            if len(link)!=1 or link[0]['firebase_uid']!=target_uid or link[0]['source_ref']!=plan['source_ref']:reject('Imported wallet link is inconsistent')
            for entry in plan['entries']:
                if entry['coin_delta']==0 and entry['diamond_delta']==0:continue
                saved=db.execute('SELECT * FROM account_wallet_ledger WHERE reference=?',(entry['reference'],)).fetchone()
                if not saved or (saved['firebase_uid'],saved['coin_delta'],saved['diamond_delta'],saved['kind'],saved['created_at'])!=(target_uid,entry['coin_delta'],entry['diamond_delta'],'verified_import',entry['created_at']):reject('Imported ledger history is inconsistent')
            coins,diamonds=totals()
            db.rollback()
            return {'saved':True,'duplicate':True,'uid':target_uid,'public_id':plan['public_id'],'coins':str(coins),'diamonds':str(diamonds),'opening_coins':str(plan['coins']),'opening_diamonds':str(plan['diamonds'])}
        if link or db.execute('SELECT 1 FROM account_wallet_ledger WHERE firebase_uid=?',(target_uid,)).fetchone():reject('An existing local wallet must be reconciled; balances were not overwritten')
        result={'saved':apply,'duplicate':False,'uid':target_uid,'public_id':plan['public_id'],'coins':str(plan['coins']),'diamonds':str(plan['diamonds'])}
        if not apply:
            db.rollback();return result
        now=int(time.time())
        db.execute('INSERT INTO account_wallet_links VALUES(?,?,?,?)',(target_uid,plan['source_ref'],now,'active'))
        for entry in plan['entries']:
            if entry['coin_delta']==0 and entry['diamond_delta']==0:continue
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',(entry['reference'],target_uid,entry['coin_delta'],entry['diamond_delta'],'verified_import',entry['created_at']))
        db.execute('INSERT INTO account_wallet_imports VALUES(?,?,?,?,?,?,?,?,?)',(plan['source_ref'],target_uid,plan['public_id'],plan['snapshot_id'],plan['snapshot_hash'],plan['coins'],plan['diamonds'],plan['proof'],now))
        if totals()!=(plan['coins'],plan['diamonds']):reject('Import reconciliation failed')
        db.execute('INSERT INTO account_control_audit(actor,action,target,payload,created_at) VALUES(?,?,?,?,?)',(target_uid,'wallet.legacy_import',target_uid,json.dumps({'source_ref':plan['source_ref'],'snapshot_hash':plan['snapshot_hash'],'coins':str(plan['coins']),'diamonds':str(plan['diamonds'])}),now))
        db.commit();return result
    except Exception:
        db.rollback();raise
    finally:db.close()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',default='/var/lib/sovera-account/profiles.sqlite3')
    parser.add_argument('--uid')
    parser.add_argument('--owner',action='store_true')
    parser.add_argument('--manifest',required=True)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Root server console required')
    if not (args.owner or args.uid):parser.error('Select --owner or the confirmed --uid')
    if args.manifest=='-':
        manifest=json.load(sys.stdin)
    else:
        path=Path(args.manifest)
        if path.stat().st_mode&0o077:parser.error('Manifest must be private: chmod 600 the file')
        manifest=json.loads(path.read_text())
    if not Path(args.database).is_file():parser.error('Existing database required')
    # Schema comes from the deployed server; never create an empty replacement DB.
    if args.apply:
        backup=Path(args.database).with_name('profiles.before-wallet-import-'+str(time.time_ns())+'.sqlite3')
        source=sqlite3.connect('file:'+str(args.database)+'?mode=ro',uri=True)
        destination=sqlite3.connect(str(backup))
        try:source.backup(destination)
        finally:destination.close();source.close()
        os.chmod(backup,0o600)
        print('Wallet database backup:',backup)
    try:result=import_wallet(args.database,manifest,target_uid=args.uid,owner=args.owner,apply=args.apply)
    except ImportRejected as error:parser.error(str(error))
    print('WALLET_IMPORT_OK' if result['saved'] else 'WALLET_IMPORT_PREVIEW')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
