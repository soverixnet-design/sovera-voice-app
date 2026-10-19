"""Uvicorn factory: server.food.runtime:create --factory.

Intentionally refuses activation until the one-wallet migration is confirmed.
No service-account JSON, owner key or browser credential belongs in the repo.
"""
import os
from pathlib import Path
from .app import create_app
from .engine import Engine
from .identity import FirebaseIdentity

def create():
    if os.environ.get('SOVERA_FOOD_WALLET_READY') != '1':
        raise RuntimeError('Food disabled: authoritative app wallet migration not confirmed')
    if os.environ.get('SOVERA_FIREBASE_PROJECT') != 'sovera-app-7d1d6':
        raise RuntimeError('Unexpected Firebase project')
    path=Path(os.environ['SOVERA_WALLET_DATABASE'])
    # Use the SAME migrated app ledger, never silently create a second wallet.
    if not path.is_absolute() or not path.is_file():
        raise RuntimeError('Existing absolute app wallet database required')
    import firebase_admin
    from firebase_admin import auth, firestore
    app=firebase_admin.initialize_app(options={'projectId':'sovera-app-7d1d6'},name='sovera-food')
    identity=FirebaseIdentity(auth,firestore.client(app=app),app)
    engine=Engine(path,can_autoplay=identity.eligible)
    return create_app(engine,identity.verify,identity.owner)
