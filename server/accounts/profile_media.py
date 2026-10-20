"""Bounded, sanitized gallery photos, stored separately from admin assets."""
import asyncio
import hashlib
import io
import sqlite3
import warnings
from PIL import Image, ImageOps, UnidentifiedImageError
from fastapi import HTTPException, Request
from fastapi.responses import Response

MAX_UPLOAD = 8 * 1024 * 1024
PUBLIC = 'https://voice.soverixnet.com/sovera/account/avatar/'

def sanitize(data):
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                if image.format not in ('JPEG', 'PNG', 'WEBP') or image.width * image.height > 16_000_000:
                    raise ValueError()
                image = ImageOps.exif_transpose(image)
                image.thumbnail((768, 768))
                output = io.BytesIO()
                image.convert('RGB').save(output, 'WEBP', quality=85)
                return output.getvalue()
    except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise HTTPException(400, 'Choose a JPEG, PNG or WebP photo up to 16 megapixels') from None

def attach_profile_media(app, profiles, actor):
    with sqlite3.connect(profiles.path) as db:
        db.execute('CREATE TABLE IF NOT EXISTS account_avatar_photos(uid TEXT NOT NULL, key TEXT PRIMARY KEY, data BLOB NOT NULL)')

    def save(uid, data):
        photo = sanitize(data)
        key = hashlib.sha256(uid.encode() + photo).hexdigest()
        with sqlite3.connect(profiles.path, timeout=10) as db:
            db.execute('BEGIN IMMEDIATE')
            total = db.execute('SELECT COALESCE(SUM(length(data)),0) FROM account_avatar_photos WHERE uid<>?', (uid,)).fetchone()[0]
            if total + len(photo) > 256 * 1024 * 1024:
                raise HTTPException(507, 'Photo storage is full')
            current = db.execute('SELECT avatar_url FROM account_profiles WHERE firebase_uid=?', (uid,)).fetchone()
            keep = current[0].removeprefix(PUBLIC) if current and current[0] else ''
            db.execute('DELETE FROM account_avatar_photos WHERE uid=? AND key<>?', (uid, keep))
            db.execute('INSERT OR IGNORE INTO account_avatar_photos VALUES(?,?,?)', (uid, key, photo))
        return {'avatar_url': PUBLIC + key}

    @app.post('/sovera/account/avatar')
    async def upload(request: Request):
        uid = await actor(request.headers.get('authorization'))
        data = bytearray()
        async for chunk in request.stream():
            data.extend(chunk)
            if len(data) > MAX_UPLOAD: raise HTTPException(413, 'Photo is too large')
        return await asyncio.to_thread(save, uid, bytes(data))

    @app.get('/sovera/account/avatar/{key}')
    def photo(key: str):
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key): raise HTTPException(404)
        with sqlite3.connect(profiles.path) as db:
            row = db.execute('SELECT data FROM account_avatar_photos WHERE key=?', (key,)).fetchone()
        if row is None: raise HTTPException(404)
        return Response(bytes(row[0]), media_type='image/webp', headers={'X-Content-Type-Options':'nosniff','Cache-Control':'public, max-age=3600'})
