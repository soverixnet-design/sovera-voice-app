"""Persistent room-based two-player XO duel; no real-money or Coin wagers."""
import time
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, StrictInt
from .rooms import Rooms

LINES=((0,1,2),(3,4,5),(6,7,8),(0,3,6),(1,4,7),(2,5,8),(0,4,8),(2,4,6))

class MoveInput(BaseModel):
    model_config=ConfigDict(extra='forbid')
    cell:StrictInt
    revision:StrictInt

class RoomDuel:
    def __init__(self,path,clock=time.time):
        self.rooms=Rooms(path,clock=clock)
        self.clock=clock
        with self.rooms.db() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS account_room_duels(
              room_id TEXT PRIMARY KEY,player_x TEXT NOT NULL,player_o TEXT,
              board TEXT NOT NULL,turn_uid TEXT,winner TEXT,
              revision INTEGER NOT NULL,updated_at REAL NOT NULL)""")

    def _require_active(self,db,room,uid):
        self.rooms.exists(db,room)
        self.rooms.profile(db,uid)
        found=db.execute("""SELECT 1 FROM account_presence
            WHERE uid=? AND room_id=? AND seen_at>?""",
            (uid,room,self.clock()-90)).fetchone()
        if not found:
            raise HTTPException(409,'Join this room to play')

    def _snapshot(self,db,room):
        row=db.execute('SELECT * FROM account_room_duels WHERE room_id=?',(room,)).fetchone()
        if not row:
            return {'ready':False,'board':list('.........'),'player_x':None,
                    'player_o':None,'turn_uid':None,'winner':None,'revision':0,'name_x':None,'name_o':None}
        r=dict(row)
        names={}
        for mark in ('x','o'):
            uid=r['player_'+mark]
            if uid:
                p=db.execute('SELECT display_name FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
                names['name_'+mark]=p['display_name'] if p else None
            else:
                names['name_'+mark]=None
        return {'ready':r['player_o'] is not None,'board':list(r['board']),
                'player_x':r['player_x'],'player_o':r['player_o'],
                'turn_uid':r['turn_uid'],'winner':r['winner'],
                'revision':r['revision'],**names}

    def state(self,room):
        with self.rooms.db() as db:
            self.rooms.exists(db,room)
            return self._snapshot(db,room)

    def join(self,uid,room):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            state=self._snapshot(db,room)
            if state['player_x'] is None:
                db.execute("""INSERT INTO account_room_duels
                    (room_id,player_x,board,turn_uid,revision,updated_at)
                    VALUES(?,?,'.........',?,1,?)""",(room,uid,uid,self.clock()))
            elif state['player_o'] is None and state['player_x']!=uid:
                db.execute("""UPDATE account_room_duels SET player_o=?,revision=revision+1,updated_at=?
                    WHERE room_id=?""",(uid,self.clock(),room))
            elif uid not in (state['player_x'],state['player_o']):
                raise HTTPException(409,'Both player slots are occupied')
            return self._snapshot(db,room)

    def move(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            state=self._snapshot(db,room)
            if not state['ready'] or state['winner'] is not None:
                raise HTTPException(409,'No active duel')
            if uid!=state['turn_uid'] or data.revision!=state['revision']:
                raise HTTPException(409,'Not your turn or board changed; refresh')
            if not 0<=data.cell<9 or state['board'][data.cell]!='.':
                raise HTTPException(422,'Invalid cell')
            mark='X' if uid==state['player_x'] else 'O'
            board=state['board']
            board[data.cell]=mark
            winner=mark if any(all(board[i]==mark for i in line) for line in LINES) else (
                'draw' if '.' not in board else None)
            following=None if winner else (
                state['player_o'] if mark=='X' else state['player_x'])
            db.execute("""UPDATE account_room_duels SET board=?,turn_uid=?,winner=?,
                revision=revision+1,updated_at=? WHERE room_id=?""",
                (''.join(board),following,winner,self.clock(),room))
            return self._snapshot(db,room)

    def restart(self,uid,room):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            state=self._snapshot(db,room)
            if uid not in (state['player_x'],state['player_o']) or state['winner'] is None:
                raise HTTPException(409,'A completed duel and an existing player are required')
            db.execute("""UPDATE account_room_duels SET board='.........',turn_uid=player_x,
                winner=NULL,revision=revision+1,updated_at=? WHERE room_id=?""",
                (self.clock(),room))
            return self._snapshot(db,room)
