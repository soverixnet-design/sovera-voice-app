"""One server-authoritative free color game shared by all signed-in users.

All rooms observe the same round and winning color. The game is not a wager
and NEVER reads, credits, or debits the wallet.
"""
import secrets
import sqlite3
import time
from typing import Literal
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, StrictInt
from .rooms import Rooms

COLORS=('red','blue','green','gold')
PICK_SECONDS=25
REVEAL_SECONDS=10
BREAK_SECONDS=5
ROUND_SECONDS=PICK_SECONDS+REVEAL_SECONDS+BREAK_SECONDS

class ColorPick(BaseModel):
    model_config=ConfigDict(extra='forbid')
    round:StrictInt
    choice:Literal['red','blue','green','gold']

class GlobalColors:
    def __init__(self,path,clock=time.time,draw=None):
        self.rooms=Rooms(path,clock=clock)
        self.clock=clock
        self.draw=draw or (lambda: secrets.choice(COLORS))
        with self.rooms.db() as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS account_global_color_rounds(
                id INTEGER PRIMARY KEY,started_at REAL NOT NULL,
                result TEXT, settled_at REAL,
                CHECK(result IS NULL OR result IN ('red','blue','green','gold')));
            CREATE TABLE IF NOT EXISTS account_global_color_picks(
                round_id INTEGER NOT NULL REFERENCES account_global_color_rounds(id),
                user_id TEXT NOT NULL,choice TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(round_id,user_id),
                CHECK(choice IN ('red','blue','green','gold')));
            CREATE INDEX IF NOT EXISTS global_colors_round_choice
                ON account_global_color_picks(round_id,choice);
            """)

    def _advance(self,db,now):
        current=db.execute('SELECT * FROM account_global_color_rounds ORDER BY id DESC LIMIT 1').fetchone()
        if current is None:
            db.execute('INSERT INTO account_global_color_rounds(id,started_at) VALUES(1,?)',(now,))
        else:
            end=current['started_at']+PICK_SECONDS
            if now>=end and current['result'] is None:
                result=self.draw()
                if result not in COLORS:
                    raise ValueError('Invalid authoritative draw')
                db.execute("""UPDATE account_global_color_rounds SET result=?,settled_at=?
                    WHERE id=? AND result IS NULL""",(result,now,current['id']))
            if now>=current['started_at']+ROUND_SECONDS:
                # Do not invent missed rounds after the service has been offline.
                db.execute('INSERT INTO account_global_color_rounds(id,started_at) VALUES(?,?)',
                           (current['id']+1,now))
        return db.execute('SELECT * FROM account_global_color_rounds ORDER BY id DESC LIMIT 1').fetchone()

    def _snapshot(self,db,uid,current,now):
        start=current['started_at']
        round_id=current['id']
        delta=now-start
        if delta<PICK_SECONDS:
            phase='pick'
            ends=start+PICK_SECONDS
        elif delta<PICK_SECONDS+REVEAL_SECONDS:
            phase='reveal'
            ends=start+PICK_SECONDS+REVEAL_SECONDS
        else:
            phase='break'
            ends=start+ROUND_SECONDS
        result=current['result'] if phase!='pick' else None
        mine=db.execute("""SELECT choice FROM account_global_color_picks
            WHERE round_id=? AND user_id=?""",(round_id,uid)).fetchone()
        count=db.execute('SELECT count(*) FROM account_global_color_picks WHERE round_id=?',
                         (round_id,)).fetchone()[0]
        winner_count=0
        winners=[]
        if result:
            winner_count=db.execute("""SELECT count(*) FROM account_global_color_picks
                WHERE round_id=? AND choice=?""",(round_id,result)).fetchone()[0]
            rows=db.execute("""SELECT p.user_id,COALESCE(a.display_name,'Player') AS name
                FROM account_global_color_picks p
                LEFT JOIN account_profiles a ON a.firebase_uid=p.user_id
                WHERE p.round_id=? AND p.choice=?
                ORDER BY p.created_at,p.user_id LIMIT 20""",(round_id,result)).fetchall()
            winners=[{'uid':r['user_id'],'name':r['name']} for r in rows]
        history=db.execute("""SELECT r.id,r.result,r.settled_at,
             (SELECT count(*) FROM account_global_color_picks p
              WHERE p.round_id=r.id AND p.choice=r.result) AS winner_count
             FROM account_global_color_rounds r
             WHERE r.result IS NOT NULL ORDER BY r.id DESC LIMIT 8""").fetchall()
        return {'game':'global-colors','round':round_id,'phase':phase,
                'server_now_ms':int(now*1000),'phase_ends_ms':int(ends*1000),
                'round_ends_ms':int((start+ROUND_SECONDS)*1000),
                'choices':list(COLORS),'pick_count':count,
                'my_pick':mine['choice'] if mine else None,
                'result':result,'winner_count':winner_count,
                'winners':winners,'my_win':bool(mine and result and mine['choice']==result),
                'history':[{'round':r['id'],'result':r['result'],
                            'winner_count':r['winner_count'],
                            'settled_at_ms':int(r['settled_at']*1000)} for r in history]}

    def state(self,uid):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.rooms.profile(db,uid)
            now=self.clock()
            current=self._advance(db,now)
            return self._snapshot(db,uid,current,now)

    def pick(self,uid,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.rooms.profile(db,uid)
            now=self.clock()
            current=self._advance(db,now)
            previous=db.execute("""SELECT choice FROM account_global_color_picks
                WHERE user_id=? AND round_id=?""",(uid,data.round)).fetchone()
            if previous and previous['choice']==data.choice:
                # Idempotent network retry does not count as another pick.
                return self._snapshot(db,uid,current,now)
            if data.round!=current['id'] or now>=current['started_at']+PICK_SECONDS:
                raise HTTPException(409,'Round closed; refresh the game')
            if previous:
                raise HTTPException(409,'Pick already locked for this round')
            db.execute("""INSERT INTO account_global_color_picks
                (round_id,user_id,choice,created_at) VALUES(?,?,?,?)""",
                (current['id'],uid,data.choice,now))
            return self._snapshot(db,uid,current,now)
