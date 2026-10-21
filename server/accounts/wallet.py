"""Read-only Sovera-owned Coin/Diamond ledger during Firebase-auth migration.

Firebase proves identity ONLY. This SQLite state must be reconciled against the
legacy wallet by a trusted migration before a wallet is linked. In particular,
an absent migration is NOT a zero balance. No app-accessible credit/bet/recharge
endpoint exists; nobody can mint coins by modifying a client request.
"""
import sqlite3
import time
import uuid
from pydantic import BaseModel, ConfigDict, Field
from .greedy_wallet import configured
from fastapi import HTTPException

class ExchangeInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    diamonds:int=Field(strict=True,ge=100,le=9007199254740991)
    request_id:uuid.UUID

class WalletStore:
    def __init__(self, database_path):
        self.database_path=str(database_path)
        with sqlite3.connect(self.database_path, timeout=10) as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS account_wallet_exchanges(
              request_id TEXT PRIMARY KEY,uid TEXT NOT NULL,diamonds INTEGER NOT NULL,
              coins INTEGER NOT NULL,created_at INTEGER NOT NULL);
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
            CREATE TABLE IF NOT EXISTS account_wallet_imports(
              source_ref TEXT PRIMARY KEY,
              firebase_uid TEXT NOT NULL UNIQUE,
              public_id TEXT NOT NULL UNIQUE,
              snapshot_id TEXT NOT NULL UNIQUE,
              snapshot_hash TEXT NOT NULL,
              opening_coins INTEGER NOT NULL,
              opening_diamonds INTEGER NOT NULL,
              proof TEXT NOT NULL,
              imported_at INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS account_wallet_history
              ON account_wallet_ledger(firebase_uid,created_at DESC,reference DESC);
            """)

    def provision(self,uid):
        """Create a native server wallet once; never replace an imported balance."""
        import os
        if os.getenv('SOVERA_AUTO_WALLETS')!='1':return
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('CREATE TABLE IF NOT EXISTS account_member_created(uid TEXT PRIMARY KEY,created_at INTEGER NOT NULL)')
            db.execute('INSERT OR IGNORE INTO account_member_created SELECT ?,? WHERE NOT EXISTS(SELECT 1 FROM account_profiles WHERE firebase_uid=?)',(uid,int(time.time()),uid))
            db.execute("INSERT OR IGNORE INTO account_profiles(firebase_uid,display_name,country,bio,updated_at) VALUES(?,'Sovera member','','',?)",(uid,int(time.time())))
            from .members import public_id
            public_id(db,uid)
            if db.execute('SELECT 1 FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone():return
            if db.execute('SELECT 1 FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone():raise HTTPException(409,'Wallet reconciliation required')
            db.execute('INSERT INTO account_wallet_links VALUES(?,?,?,?)',(uid,'sovera-native:'+uid,int(time.time()),'active'))

    def state(self, uid):
        # Do not create a wallet on login or give a fake zero balance.
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.row_factory=sqlite3.Row
            link=db.execute("""SELECT status,verified_at FROM account_wallet_links
                WHERE firebase_uid=?""",(uid,)).fetchone()
            if link is None:
                return {'status':'not_migrated','verified':False,
                        'coins':None,'diamonds':None,'canSpend':False,
                        'canPurchase':False,'canGift':False,'source':'sovera-server'}
            coins,diamonds=db.execute("""SELECT COALESCE(SUM(coin_delta),0),
                    COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger
                    WHERE firebase_uid=?""",(uid,)).fetchone()
            if coins<0 or diamonds<0 or coins>9007199254740991 or diamonds>9007199254740991:
                raise HTTPException(503,'Wallet reconciliation required')
            # Game spending remains disabled until trusted atomic bet settlement
            # is connected to this same ledger transaction boundary.
            return {'status':link['status'],'verified':True,
                    'coins':str(coins),'diamonds':str(diamonds),
                    'canSpend':link['status']=='active' and configured(),
                    'canPurchase':link['status']=='active','canGift':link['status']=='active',
                    'source':'sovera-server'}

    def exchange(self,uid,data):
        if data.diamonds%100:raise HTTPException(400,'Enter Diamonds in multiples of 100')
        credit=data.diamonds//100*70
        request=str(data.request_id)
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.execute('BEGIN IMMEDIATE')
            prior=db.execute('SELECT uid,diamonds,coins FROM account_wallet_exchanges WHERE request_id=?',(request,)).fetchone()
            if prior:
                if prior!=(uid,data.diamonds,credit):raise HTTPException(409,'Exchange request already used')
                return {'saved':True,'coins_received':str(credit),'diamonds_spent':str(data.diamonds),'request_id':request}
            link=db.execute('SELECT status,verified_at FROM account_wallet_links WHERE firebase_uid=?',(uid,)).fetchone()
            if not link or link[0]!='active' or link[1]<=0:raise HTTPException(409,'Active verified wallet required')
            coins,diamonds=db.execute('SELECT COALESCE(SUM(coin_delta),0),COALESCE(SUM(diamond_delta),0) FROM account_wallet_ledger WHERE firebase_uid=?',(uid,)).fetchone()
            if not 0<=coins<=9007199254740991 or not 0<=diamonds<=9007199254740991:raise HTTPException(409,'Wallet reconciliation required')
            if diamonds<data.diamonds:raise HTTPException(409,'Insufficient Diamonds')
            if coins+credit>9007199254740991:raise HTTPException(409,'Coin balance limit reached')
            now=int(time.time())
            db.execute('INSERT INTO account_wallet_ledger VALUES(?,?,?,?,?,?)',('diamond-exchange:'+request,uid,credit,-data.diamonds,'exchange',now))
            db.execute('INSERT INTO account_wallet_exchanges VALUES(?,?,?,?,?)',(request,uid,data.diamonds,credit,now))
            return {'saved':True,'coins_received':str(credit),'diamonds_spent':str(data.diamonds),'request_id':request}

    def history(self,uid,limit=30,before_time=None,before_ref=None):
        with sqlite3.connect(self.database_path,timeout=10) as db:
            db.row_factory=sqlite3.Row
            link=db.execute("""SELECT 1 FROM account_wallet_links
                 WHERE firebase_uid=?""",(uid,)).fetchone()
            if link is None:return []
            cursor=''
            params=[uid]
            if before_time is not None and before_ref is not None:
                cursor=' AND (created_at < ? OR (created_at = ? AND reference < ?))'
                params.extend([before_time,before_time,before_ref])
            params.append(limit)
            return [dict(row) for row in db.execute("""SELECT reference,kind,
                coin_delta,diamond_delta,created_at FROM account_wallet_ledger
                WHERE firebase_uid=?"""+cursor+""" ORDER BY created_at DESC,reference DESC
                LIMIT ?""",params).fetchall()]

    def has_verified_wallets(self):
        with sqlite3.connect(self.database_path,timeout=10) as db:
            return db.execute("SELECT EXISTS(SELECT 1 FROM account_wallet_links WHERE status='active' AND verified_at>0)").fetchone()[0]==1

def legacy_identity(db,uid):
    from .members import public_id
    return {'public_id':public_id(db,uid)}
