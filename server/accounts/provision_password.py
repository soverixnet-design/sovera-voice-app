"""Root-console setup/reset. Passwords are prompted, never command arguments."""
import argparse
import getpass
import os
import sqlite3
from .control import Control
from .control_password import Passwords

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--database',default='/var/lib/sovera-account/profiles.sqlite3')
    parser.add_argument('--uid')
    parser.add_argument('--single-owner',action='store_true')
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Root server console required')
    if not os.isatty(0):parser.error('Interactive console required')
    if not os.path.isfile(args.database):parser.error('Existing database required')
    control=Control(args.database)
    passwords=Passwords(control)
    with control.db() as db:
        if args.single_owner:
            rows=db.execute('SELECT firebase_uid,display_name,country FROM account_profiles').fetchall()
            if len(rows)!=1:parser.error('Multiple accounts exist; select your UID using --uid')
            uid=rows[0]['firebase_uid']
            print('Your confirmed owner account:',uid,rows[0]['display_name'],rows[0]['country'])
        elif args.uid:uid=args.uid
        else:parser.error('Specify --uid or --single-owner')
        if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone():parser.error('Existing profile required')
        owners=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
        if owners and any(row['uid']!=uid for row in owners):parser.error('Another owner is already assigned')
    username=input('Admin username [soverix]: ').strip() or 'soverix'
    password=getpass.getpass('New password (12+ characters): ')
    if password!=getpass.getpass('Repeat password: '):parser.error('Passwords do not match; no access changed')
    from .control_password import username_key
    try:
        username_key(username)
        if not 12<=len(password)<=128:raise ValueError('Password must contain 12–128 characters')
    except ValueError as e:parser.error(str(e))
    with control.db() as db:
        db.execute('BEGIN IMMEDIATE')
        owners=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
        if any(row['uid']!=uid for row in owners):parser.error('Another owner is already assigned')
        db.execute("INSERT INTO account_staff VALUES(?,'owner') ON CONFLICT(uid) DO UPDATE SET role='owner'",(uid,))
        db.execute('DELETE FROM account_control_agents WHERE uid=?',(uid,))
    try:passwords.set(uid,username,password)
    except ValueError as e:parser.error(str(e))
    print('ADMIN_PASSWORD_READY')
    print('Open https://admin.soverixnet.com and sign in as',username)

if __name__=='__main__':main()
