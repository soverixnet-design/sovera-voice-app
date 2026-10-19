"""Durable single-host food rounds. No client balance/result is trusted.

Uses a dedicated ledger; do not activate against app coins before the wallet
migration and verified identity adapter are complete. No HTTP funding endpoint.
"""
import contextlib
import hashlib
import json
import secrets
import sqlite3
import time
from fractions import Fraction
from math import lcm

SLOTS = {'chk': 45, 'fish': 25, 'hot': 15, 'stk': 10,
         'grp': 5, 'let': 5, 'pep': 5, 'mel': 5}
CHIPS = (50, 500, 2000, 10000)
BET_SECONDS, SPIN_SECONDS, WAIT_SECONDS = 30, 8, 5


class Rejected(ValueError):
    pass


class Engine:
    def __init__(self, path, clock=time.time, can_autoplay=None):
        self.path, self.clock = str(path), clock
        self.can_autoplay = can_autoplay or (lambda uid: False)
        with self.transaction() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS food_rounds(
              id INTEGER PRIMARY KEY, started_at REAL NOT NULL,
              result_slot TEXT, seed_hash TEXT, seed TEXT, config TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS food_bets(
              id TEXT PRIMARY KEY, round_id INTEGER NOT NULL, user_id TEXT NOT NULL,
              slot TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount>0),
              win INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL,
              UNIQUE(user_id,id));
            CREATE TABLE IF NOT EXISTS wallet_ledger(
              reference TEXT PRIMARY KEY, user_id TEXT NOT NULL,
              delta INTEGER NOT NULL, created_at REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS ledger_user ON wallet_ledger(user_id);
            CREATE INDEX IF NOT EXISTS bets_user_round ON food_bets(user_id,round_id);
            CREATE TABLE IF NOT EXISTS food_auto(
              user_id TEXT PRIMARY KEY, slot TEXT NOT NULL, amount INTEGER NOT NULL,
              remaining INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS food_settings(
              id INTEGER PRIMARY KEY CHECK(id=1), config TEXT NOT NULL);
            ''')
            db.execute('INSERT OR IGNORE INTO food_settings VALUES(1,?)',
                       (json.dumps(SLOTS),))

    @contextlib.contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE')
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    @staticmethod
    def balance(db, uid):
        return db.execute('SELECT COALESCE(SUM(delta),0) FROM wallet_ledger WHERE user_id=?', (uid,)).fetchone()[0]

    def credit(self, uid, amount, reference):
        """Trusted migration/recharge adapter only; never expose directly to clients."""
        if type(amount) is not int or amount <= 0:
            raise Rejected('Invalid credit')
        with self.transaction() as db:
            old = db.execute('SELECT * FROM wallet_ledger WHERE reference=?', (reference,)).fetchone()
            if old and (old['user_id'], old['delta']) != (uid, amount):
                raise Rejected('Credit reference conflict')
            db.execute('INSERT OR IGNORE INTO wallet_ledger VALUES(?,?,?,?)',
                       (reference, uid, amount, self.clock()))

    @staticmethod
    def pick(config, seed):
        # Exact integer inverse-multiplier weights, no float bias.
        scale = lcm(*config.values())
        weights = [(slot, scale // multiplier) for slot, multiplier in config.items()]
        total = sum(w for _, w in weights)
        # Rejection sampling makes hash-derived draws unbiased.
        limit = (1 << 256) - ((1 << 256) % total)
        nonce = 0
        while True:
            n = int.from_bytes(hashlib.sha256(f'{seed}:{nonce}'.encode()).digest(), 'big')
            if n < limit:
                n %= total
                for slot, weight in weights:
                    if n < weight:
                        return slot
                    n -= weight
            nonce += 1

    @staticmethod
    def rtp(config):
        return float(1 / sum((Fraction(1, v) for v in config.values()), Fraction()))

    def tick(self, db, now):
        row = db.execute('SELECT * FROM food_rounds ORDER BY id DESC LIMIT 1').fetchone()
        if row and now >= row['started_at'] + BET_SECONDS and row['result_slot'] is None:
            config = json.loads(row['config'])
            seed = secrets.token_hex(32)  # Generated only AFTER betting closes.
            result = self.pick(config, seed)
            db.execute('UPDATE food_rounds SET result_slot=?,seed=?,seed_hash=? WHERE id=?',
                       (result, seed, hashlib.sha256(seed.encode()).hexdigest(), row['id']))
            for bet in db.execute('SELECT * FROM food_bets WHERE round_id=? AND slot=?', (row['id'], result)).fetchall():
                win = bet['amount'] * config[result]
                db.execute('UPDATE food_bets SET win=? WHERE id=?', (win, bet['id']))
                db.execute('INSERT INTO wallet_ledger VALUES(?,?,?,?)',
                           ('win:' + bet['id'], bet['user_id'], win, now))
        if row is None or now >= row['started_at'] + BET_SECONDS + SPIN_SECONDS + WAIT_SECONDS:
            config = db.execute('SELECT config FROM food_settings WHERE id=1').fetchone()[0]
            rid = (row['id'] + 1) if row else 1
            db.execute('INSERT INTO food_rounds(id,started_at,config) VALUES(?,?,?)', (rid, now, config))
            for auto in db.execute('SELECT * FROM food_auto WHERE remaining>0').fetchall():
                if self.can_autoplay(auto['user_id']) is True and self.balance(db, auto['user_id']) >= auto['amount']:
                    self._bet(db, auto['user_id'], rid, auto['slot'], auto['amount'],
                              f"auto:{rid}:{auto['user_id']}", now)
                    db.execute('UPDATE food_auto SET remaining=remaining-1 WHERE user_id=?', (auto['user_id'],))
                else:
                    db.execute('UPDATE food_auto SET remaining=0 WHERE user_id=?', (auto['user_id'],))
        return db.execute('SELECT * FROM food_rounds ORDER BY id DESC LIMIT 1').fetchone()

    def _bet(self, db, uid, rid, slot, amount, key, now):
        old = db.execute('SELECT * FROM food_bets WHERE id=?', (key,)).fetchone()
        if old:
            if (old['user_id'],old['round_id'],old['slot'],old['amount']) != (uid,rid,slot,amount):
                raise Rejected('Idempotency key conflict')
            return dict(old)
        row = db.execute('SELECT * FROM food_rounds ORDER BY id DESC LIMIT 1').fetchone()
        if not row or row['id'] != rid or now >= row['started_at'] + BET_SECONDS or row['result_slot']:
            raise Rejected('Betting closed')
        if slot not in json.loads(row['config']) or type(amount) is not int or amount not in CHIPS:
            raise Rejected('Invalid slot or chip')
        if self.balance(db, uid) < amount:
            raise Rejected('Insufficient balance')
        db.execute('INSERT INTO food_bets VALUES(?,?,?,?,?,0,?)', (key,rid,uid,slot,amount,now))
        db.execute('INSERT INTO wallet_ledger VALUES(?,?,?,?)', ('bet:'+key,uid,-amount,now))
        return dict(db.execute('SELECT * FROM food_bets WHERE id=?', (key,)).fetchone())

    def bet(self, uid, rid, slot, amount, key):
        if not key or len(key)>128 or key.startswith('auto:'):
            raise Rejected('Invalid idempotency key')
        with self.transaction() as db:
            now = self.clock()
            self.tick(db, now)
            result = self._bet(db,uid,rid,slot,amount,key,now)
            return {'bet':result,'balance':self.balance(db,uid)}

    def autoplay(self, uid, slot, amount, rounds):
        if slot not in SLOTS or type(amount) is not int or amount not in CHIPS or type(rounds) is not int or not 0<=rounds<=100:
            raise Rejected('Invalid autoplay plan')
        if rounds and self.can_autoplay(uid) is not True:
            raise Rejected('Autoplay not enabled for this account')
        with self.transaction() as db:
            db.execute('INSERT OR REPLACE INTO food_auto VALUES(?,?,?,?)', (uid,slot,amount,rounds))
        return {'remaining':rounds}

    def configure(self, config):
        # Caller MUST enforce owner permission; never use a client-supplied role.
        if set(config)!=set(SLOTS) or any(type(v) is not int or not 1<=v<=1000 for v in config.values()):
            raise Rejected('Invalid multipliers')
        if not .01 <= self.rtp(config) <= 1:
            raise Rejected('RTP outside supported range')
        with self.transaction() as db:
            db.execute('UPDATE food_settings SET config=? WHERE id=1', (json.dumps(config),))
        return {'rtp':self.rtp(config),'effective':'next_round'}

    def state(self, uid):
        with self.transaction() as db:
            now=self.clock(); row=self.tick(db,now); age=now-row['started_at']
            phase='bet' if age<BET_SECONDS else 'spin' if age<BET_SECONDS+SPIN_SECONDS else 'wait'
            ends=row['started_at']+(BET_SECONDS if phase=='bet' else BET_SECONDS+SPIN_SECONDS if phase=='spin' else BET_SECONDS+SPIN_SECONDS+WAIT_SECONDS)
            history=[dict(r) for r in db.execute('SELECT r.id AS round,r.result_slot AS slot,SUM(b.amount) AS myBet,SUM(b.win) AS myWin FROM food_bets b JOIN food_rounds r ON r.id=b.round_id WHERE b.user_id=? AND r.result_slot IS NOT NULL GROUP BY r.id ORDER BY r.id DESC LIMIT 30',(uid,))]
            bets={r['slot']:r['amount'] for r in db.execute('SELECT slot,SUM(amount) AS amount FROM food_bets WHERE round_id=? AND user_id=? GROUP BY slot',(row['id'],uid))}
            totals=db.execute('SELECT COALESCE(SUM(amount),0),COALESCE(SUM(win),0) FROM food_bets WHERE round_id=? AND user_id=?',(row['id'],uid)).fetchone()
            top=[{'uid':r['user_id'],'name':None,'avatar':None,'win':r['win']} for r in db.execute('SELECT user_id,SUM(win) AS win FROM food_bets WHERE round_id=? GROUP BY user_id HAVING SUM(win)>0 ORDER BY win DESC,user_id LIMIT 3',(row['id'],))]
            return {'round':row['id'],'phase':phase,'serverNow':int(now*1000),'endsAt':int(ends*1000),'balance':self.balance(db,uid),'bets':bets,'myBet':totals[0],'myWin':totals[1],'slot':row['result_slot'],'top3':top,'history':history,'results':[r[0] for r in db.execute('SELECT result_slot FROM food_rounds WHERE result_slot IS NOT NULL ORDER BY id DESC LIMIT 8')],'multipliers':json.loads(row['config']),'rtp':self.rtp(json.loads(row['config'])),'seedHash':row['seed_hash'],'seed':row['seed']}
