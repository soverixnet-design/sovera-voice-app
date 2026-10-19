# Firebase gateway migration — prepared, not deployed

Target project: `sovera-app-7d1d6`. The existing app and gateway continue to use Supabase until the complete migration is verified. Do not switch only the login screen: room/profile storage and the gateway must change together.

## Implemented here

The gateway accepts an explicit `SOVERA_AUTH_PROVIDER=firebase` mode. Set `SOVERA_FIREBASE_PROJECT` and `SOVERA_FIREBASE_PUBLIC_KEY` on the server. Google accounts:lookup verifies the caller token; subsequent Firestore reads use that same caller token in the fixed configured project. No service-account private key is included. Missing ban/closed state, invalid seat count, denied reads, and failed identity verification reject the grant. Seat leases and microphone revocation are unchanged.

The default remains Supabase. An unknown provider fails closed. Existing installer placeholders remain compatible.

## Required before activation

1. Export existing profiles/rooms and map old UUID identities to verified Firebase identities without merging accounts by unverified email. Preserve owner/admin grants only through an authenticated migration.
2. Create Firestore documents `sovera_profiles/{firebaseUid}` and `sovera_rooms/{roomUuid}`. Publish tested ownership rules. Users must not be able to change their ban, role, wallet, or ownership fields.
3. Wire the Flutter app to Firebase Auth and the new data backend together. Preserve Facebook, Google, and email choices; Facebook needs its existing Meta configuration transferred through a secure flow.
4. Use a privately held stable signing key. Register the actual built APK certificate SHA-1/SHA-256 in Firebase; refresh google-services.json. Never commit a signing private key.
5. Deploy the gateway configuration through server access. Verify real authenticated join, blocked user, closed room, two-phone audio, and seat renewal before switching users.

The checked-in public Firebase config supplied by the owner has no OAuth clients yet and is not a production-ready Google configuration. This change does not activate Firebase in the APK or modify production data.

Validation: `python server/voice/test_firebase_auth.py` and `python server/voice/test_seats.py`.
