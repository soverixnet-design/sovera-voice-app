# Sovera Supabase authentication

Project: Earnbd (`rfrmcmeyamndghtiheci`). Client uses only the public publishable key. No service role or Google secret is embedded.

Implemented:
- Google OAuth through the system browser, using PKCE.
- Android/iOS callback registration: `com.sovera.voice://login-callback`.
- Session persistence/refresh through supabase_flutter.
- Authenticated entry gate calls Auth.getUser before loading the account profile.
- Unique numeric UID from a generated database identity.
- Self-owned profile creation/read/update with database RLS.
- Profile name/bio save to the server; profile image from Google metadata.
- Client role is always `user`; role and UID cannot be edited by clients.
- Sign out clears the local session and closes nested screens.

## Blocking provider setup
The Auth settings endpoint was checked during implementation: Google is DISABLED.
The connected database tools cannot manage OAuth credentials or the Auth URL allowlist.

In Supabase Dashboard > Authentication > Sign In / Providers > Google:
1. Enable Google and add a Google Cloud WEB OAuth Client ID and Client Secret.
2. In that Google Cloud OAuth client, add this authorized redirect URI:
   `https://rfrmcmeyamndghtiheci.supabase.co/auth/v1/callback`
3. In Supabase Authentication > URL Configuration > Redirect URLs, add the exact app callback:
   `com.sovera.voice://login-callback`
4. If Google consent is in Testing, add the intended test users, or finish Google's publishing requirements.

Do not paste the Google Client Secret in chat or put it in this repository. Enter it only in Supabase's Google provider configuration. No Google Cloud billing setup is required by this code.

After setup, the app checks provider availability at runtime; a new build is not required just to enable the provider. Complete the actual Google sign-in on a physical device, close/reopen the app, save the profile and sign out. End-to-end OAuth has NOT passed until these checks succeed.

## Scope
The home and room screens remain design previews. Wallet, room presence, RTC, social feed, events and game servers are not connected by this auth change. Existing separate `earnbd` database schema and its policies were not modified.

## Verification
A rolled-back database test confirmed own profile creation/read, cross-user read/update/insert isolation and denial of role changes. Google provider availability is checked before opening the OAuth browser. Use the GitHub workflow result for static analysis, widget tests and platform builds.
