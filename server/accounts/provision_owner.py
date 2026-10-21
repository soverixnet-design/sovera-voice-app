"""Run on the actual server console to designate an existing Firebase account."""
import argparse
import os
import sqlite3

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--database',default='/var/lib/sovera-account/profiles.sqlite3')
    parser.add_argument('--uid')
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Root console access is required')
    if not os.path.isfile(args.database):parser.error('Existing account database required')
    with sqlite3.connect(args.database,timeout=10) as db:
        if not args.uid:
            print('Select YOUR existing account UID; no owner has been assigned by this command.')
            for row in db.execute('SELECT firebase_uid,display_name,country FROM account_profiles ORDER BY display_name LIMIT 200'):
                print(' | '.join(row))
            return
        db.execute('BEGIN IMMEDIATE')
        if not db.execute('SELECT 1 FROM account_profiles WHERE firebase_uid=?',(args.uid,)).fetchone():
            parser.error('UID does not match an existing saved profile')
        existing=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
        if existing and existing!=[(args.uid,)]:parser.error('Another owner is already assigned; no changes made')
        db.execute("INSERT INTO account_staff VALUES(?,'owner') ON CONFLICT(uid) DO UPDATE SET role='owner'",(args.uid,))
        db.execute('DELETE FROM account_control_agents WHERE uid=?',(args.uid,))
        print('Owner assigned to the selected existing Firebase account. Sign out and sign in to refresh the app menu.')

if __name__=='__main__':main()
