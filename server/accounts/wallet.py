"""Read-only Sovera-owned Coin/Diamond ledger during Firebase-auth migration.

Firebase proves identity ONLY. This SQLite state must be reconciled against the
legacy wallet by a trusted migration before a wallet is linked. In particular,
an absent migration is NOT a zero balance. No app-accessible credit/bet/recharge
endpoint exists; nobody can mint coins by modifying a client request.
"""
import sqlite3
from .greedy_wallet import configured
from fastapi import HTTPException

class WalletStore:
    def __init__(self, database_path):
        self.database_path=str(database_path)
        with sqlite3.connect(self.database_path, timeout=10) as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS account_wallet_links(
              firebase_uid TEXT PRIMARY KEY,
              source_ref TEXT NOT NULL UNIQUE,
              verified_at INTEGER NOT NULL CHECK(verified_at>0),
              status TEXT NOT NULL CHECK(status IN ('active','frozen')));
            CREATE TABLE IF NOT EXISTS account_wallet_ledger(
              reference TEXT PRIMARY KEY,
              firebase_uid TEXT NOT NULL REFERENCES account_wallet_links(firebase_uid),
              coin_delta INTEGER NOT NULL DEFAULT 0,
              diamond_delta INTEGER NOT NULL DEFAULT 0,
              kind TEXT NOT NULL CHECK(kind IN
                ('verified_import','recharge','gift','exchange','admin_adjust','game_debit','game_win','refund')),
              created_at INTEGER NOT NULL CHECK(created_at>0),
              CHECK(coin_delta != 0 OR diamond_delta != 0));
            CREATE INDEX IF NOT EXISTS account_wallet_history
              ON account_wallet_ledger(firebase_uid,created_at DESC,reference DESC);
            """)

    def state(self, uid):
        # Do not create a wallet on login or give a fake zero balance.
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.row_factory=sqlite3.Row
            link=db.execute("""SELECT status,verified_at FROM account_wallet_links
                WHERE firebase_uid=?""",(uid,)).fetchone()
            if link is None:
                return {'status':'not_migrated','verified':False,
                        'coins':None,'diamonds':None,'canSpend':False,
                        'source':'sovera-server'}
            coins,diamonds=db.execute("""SELECT COALESCE(SUM(coin_delta),0),
                    COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger
                    WHERE firebase_uid=?""",(uid,)).fetchone()
            if coins<0 or diamonds<0:
                raise HTTPException(503,'Wallet reconciliation required')
            # Game spending remains disabled until trusted atomic bet settlement
            # is connected to this same ledger transaction boundary.
            return {'status':link['status'],'verified':True,
                    'coins':str(coins),'diamonds':str(diamonds),
                    'canSpend':link['status']=='active' and configured(),'source':'sovera-server'}

    def history(self,uid,limit=30):
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.row_factory=sqlite3.Row
            link=db.execute("""SELECT 1 FROM account_wallet_links
                 WHERE firebase_uid=?""",(uid,)).fetchone()
            if link is None:return []
            return [dict(row) for row in db.execute("""SELECT reference,kind,
                coin_delta,diamond_delta,created_at FROM account_wallet_ledger
                WHERE firebase_uid=? ORDER BY created_at DESC,reference DESC
                LIMIT ?""",(uid,limit)).fetchall()]
