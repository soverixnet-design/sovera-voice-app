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
            db.execute("""CREATE TABLE IF NOT EXISTS account_room_duel_queue(
              room_id TEXT NOT NULL,user_id TEXT NOT NULL,enqueued_at REAL NOT NULL,
              PRIMARY KEY(room_id,user_id))""")
            db.execute("""CREATE INDEX IF NOT EXISTS account_duel_queue_order
              ON account_room_duel_queue(room_id,enqueued_at,user_id)""")

    def _require_active(self,db,room,uid):
        self.rooms.exists(db,room)
        self.rooms.profile(db,uid)
        found=db.execute("""SELECT 1 FROM account_presence
            WHERE uid=? AND room_id=? AND seen_at>?""",
            (uid,room,self.clock()-90)).fetchone()
        if not found:
            raise HTTPException(409,'Join this room to play')

    def _expire_idle(self,db,room,now):
        """Resolve abandoned/inactive games without inventing a winner.
        Call inside a write transaction, ensuring every viewer sees one state.
        """
        row=db.execute("""SELECT updated_at,winner FROM account_room_duels
            WHERE room_id=?""",(room,)).fetchone()
        if row is not None and row['winner'] is None and now-row['updated_at']>=120:
            db.execute("""UPDATE account_room_duels
                SET winner='timeout',turn_uid=NULL,revision=revision+1,updated_at=?
                WHERE room_id=? AND winner IS NULL""",(now,room))

    def _snapshot(self,db,room,viewer=None):
        waiting=db.execute("""SELECT user_id FROM account_room_duel_queue
            WHERE room_id=? ORDER BY enqueued_at,user_id""",(room,)).fetchall()
        queue=[r['user_id'] for r in waiting]
        queued_position=queue.index(viewer)+1 if viewer in queue else None
        queue_info={'waiting_count':len(queue),'my_waiting_position':queued_position,
                    'next_allowed_at_ms':None}

        row=db.execute('SELECT * FROM account_room_duels WHERE room_id=?',(room,)).fetchone()
        if not row:
            return {'ready':False,'board':list('.........'),'player_x':None,
                    'player_o':None,'turn_uid':None,'winner':None,'revision':0,'name_x':None,'name_o':None,
                    **queue_info}
        r=dict(row)
        names={}
        for mark in ('x','o'):
            uid=r['player_'+mark]
            if uid:
                p=db.execute('SELECT display_name FROM account_profiles WHERE firebase_uid=?',(uid,)).fetchone()
                names['name_'+mark]=p['display_name'] if p else None
            else:
                names['name_'+mark]=None
        if r['winner'] is not None:
            queue_info['next_allowed_at_ms']=int((r['updated_at']+5)*1000)
        return {'ready':r['player_o'] is not None,'board':list(r['board']),
                'player_x':r['player_x'],'player_o':r['player_o'],
                'turn_uid':r['turn_uid'],'winner':r['winner'],
                'revision':r['revision'],**names,**queue_info}

    def state(self,room,viewer=None):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self.rooms.exists(db,room)
            self._expire_idle(db,room,self.clock())
            return self._snapshot(db,room,viewer)

    def join(self,uid,room):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            self._expire_idle(db,room,self.clock())
            state=self._snapshot(db,room)
            if state['player_x'] is None:
                db.execute("""INSERT INTO account_room_duels
                    (room_id,player_x,board,turn_uid,revision,updated_at)
                    VALUES(?,?,'.........',?,1,?)""",(room,uid,uid,self.clock()))
            elif state['player_o'] is None and state['player_x']!=uid:
                db.execute("""UPDATE account_room_duels SET player_o=?,revision=revision+1,updated_at=?
                    WHERE room_id=?""",(uid,self.clock(),room))
            elif uid not in (state['player_x'],state['player_o']):
                db.execute("""INSERT OR IGNORE INTO account_room_duel_queue
                    (room_id,user_id,enqueued_at) VALUES(?,?,?)""",(room,uid,self.clock()))
            return self._snapshot(db,room,uid)

    def move(self,uid,room,data):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            self._expire_idle(db,room,self.clock())
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
            return self._snapshot(db,room,uid)

    def cancel_wait(self,uid,room):
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            db.execute('DELETE FROM account_room_duel_queue WHERE room_id=? AND user_id=?',(room,uid))
            return self._snapshot(db,room,uid)

    def restart(self,uid,room):
        """Any present user may launch the next match after a visible winner.
        Waiting participants have first priority; current players are fallback.
        No participant's game is interrupted, and no fabricated winners exist.
        """
        with self.rooms.db() as db:
            db.execute('BEGIN IMMEDIATE')
            self._require_active(db,room,uid)
            now=self.clock()
            self._expire_idle(db,room,now)
            state=self._snapshot(db,room,uid)
            if state['winner'] is None:
                raise HTTPException(409,'Finish the current game first')
            match=db.execute('SELECT updated_at FROM account_room_duels WHERE room_id=?',(room,)).fetchone()
            if now<match['updated_at']+5:
                raise HTTPException(409,'Winner display is still active')
            # Remove users whose room heartbeat expired; they cannot be selected.
            db.execute("""DELETE FROM account_room_duel_queue WHERE room_id=?
              AND NOT EXISTS(SELECT 1 FROM account_presence a WHERE a.uid=account_room_duel_queue.user_id
                AND a.room_id=account_room_duel_queue.room_id AND a.seen_at>?)""",(room,now-90))
            # A spectator pressing "Next match" is automatically queued.
            if uid not in (state['player_x'],state['player_o']):
                db.execute("""INSERT OR IGNORE INTO account_room_duel_queue
                    (room_id,user_id,enqueued_at) VALUES(?,?,?)""",(room,uid,now))
            rows=db.execute("""SELECT user_id FROM account_room_duel_queue
                WHERE room_id=? ORDER BY enqueued_at,user_id""",(room,)).fetchall()
            candidates=[r['user_id'] for r in rows]
            # Fill remaining seats with present players from the previous match.
            for old in (state['player_x'],state['player_o']):
                if old not in candidates and old is not None:
                    active=db.execute("""SELECT 1 FROM account_presence
                        WHERE uid=? AND room_id=? AND seen_at>?""",(old,room,now-90)).fetchone()
                    if active:
                        candidates.append(old)
            if len(candidates)==0:
                raise HTTPException(409,'No online player in this room')
            x=candidates[0]
            o=candidates[1] if len(candidates)>1 else None
            db.execute("""UPDATE account_room_duels
                SET player_x=?,player_o=?,board='.........',turn_uid=?,winner=NULL,
                    revision=revision+1,updated_at=? WHERE room_id=?""",
                (x,o,x,now,room))
            for selected in (x,o):
                if selected:
                    db.execute("""DELETE FROM account_room_duel_queue
                        WHERE room_id=? AND user_id=?""",(room,selected))
            return self._snapshot(db,room,uid)
