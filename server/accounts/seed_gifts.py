"""Seed animated gifts and the supplied room's eight gifts, preserving owner edits."""
import io
import math
import time
import uuid
from PIL import Image,ImageDraw
from .catalog import Catalog
from .original_gift_art import image as original_artwork

GIFTS=(('Love Heart',10,(255,70,140)),('Diamond',100,(70,220,255)),
       ('Royal Crown',500,(255,200,70)),('Lucky Star',1000,(180,110,255)))
NAMESPACE=uuid.UUID('4be4c136-d521-427d-bc6f-8732a342c8d3')
ROOM_GIFTS=(('rose','Rose',5),('ring','Ring',50),('car','Car',500),
            ('castle','Castle',1000),('lion','Lion',2000),('dragon','Dragon',5000),
            ('rocket','Rocket',9900),('crown','Crown',19900))

def artwork(kind,color):
    frames=[]
    for index in range(24):
        phase=index/24*2*math.pi
        scale=.85+.08*math.sin(phase)
        image=Image.new('RGBA',(256,256));draw=ImageDraw.Draw(image)
        def points(values):return [(128+(x-128)*scale,128+(y-128)*scale) for x,y in values]
        if kind==0:
            values=[(128+5*(16*math.sin(t)**3),128-5*(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t))) for t in [i*math.pi/90 for i in range(180)]]
        elif kind==1:values=[(75,62),(181,62),(217,110),(128,213),(39,110)]
        elif kind==2:values=[(45,185),(28,78),(87,123),(128,47),(169,123),(228,78),(211,185)]
        else:values=[(128+90* (1 if i%2==0 else .45)*math.sin(i*math.pi/5),128-90*(1 if i%2==0 else .45)*math.cos(i*math.pi/5)) for i in range(10)]
        draw.polygon(points(values),fill=(*color,235))
        draw.line(points(values+[values[0]]),fill=(255,245,255,255),width=3)
        if kind==1:
            for a,b in [((75,62),(128,213)),((181,62),(128,213)),((39,110),(217,110))]:draw.line(points([a,b]),fill=(235,255,255,255),width=2)
        for star in range(7):
            angle=phase+star*math.pi*2/7
            x,y=128+110*math.cos(angle),128+110*math.sin(angle)
            draw.line((x-3,y,x+3,y),fill=(*color,220),width=2)
            draw.line((x,y-3,x,y+3),fill=(*color,220),width=2)
        frames.append(image)
    data=io.BytesIO()
    frames[0].save(data,format='WEBP',save_all=True,append_images=frames[1:],duration=65,loop=0,quality=80)
    return data.getvalue()

def seed(database):
    catalog=Catalog(database)
    with catalog.control.db() as db:
        owners=db.execute("SELECT uid FROM account_staff WHERE role='owner'").fetchall()
        if len(owners)!=1:raise ValueError('Exactly one owner required')
        owner=owners[0]['uid']
    added=0
    for index,(title,price,color) in enumerate(GIFTS):
        key=str(uuid.uuid5(NAMESPACE,title))
        with catalog.control.db() as db:
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
        media=catalog.upload(owner,artwork(index,color))
        with catalog.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
            db.execute('INSERT INTO account_catalog VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                (key,'gift',title,media['id'],price,1,100+index,.46,.5,.5,int(time.time())))
            catalog.control.audit(db,owner,'catalog.seed_gift',key,{'title':title,'price':price})
            added+=1
    for index,(name,title,price) in enumerate(ROOM_GIFTS):
        key=str(uuid.uuid5(NAMESPACE,'original-room:'+name))
        with catalog.control.db() as db:
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
        media=catalog.upload(owner,original_artwork(name))
        with catalog.control.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT 1 FROM account_catalog WHERE id=?',(key,)).fetchone():continue
            db.execute('INSERT INTO account_catalog VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                (key,'gift',title,media['id'],price,1,104+index,.46,.5,.5,int(time.time())))
            catalog.control.audit(db,owner,'catalog.seed_gift',key,{'title':title,'price':price})
            added+=1
    return {'added':added,'total':len(GIFTS)+len(ROOM_GIFTS)}

if __name__=='__main__':
    import argparse,os
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',default='/var/lib/sovera-account/profiles.sqlite3')
    args=parser.parse_args()
    if os.geteuid()!=0:parser.error('Root server session required')
    print(seed(args.database))
