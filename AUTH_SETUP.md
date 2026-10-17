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

## Facebook sign-in (0.13.1)

The sign-in screen now contains Continue with Facebook and Continue with Google.
Guests can open it with Sign in / Create account from the home header.
Successful sign-in returns to the authenticated account instead of leaving a guest route above it.

Facebook provider was enabled on Supabase on 18 October 2026; the public Auth settings endpoint reports Facebook enabled and Google disabled. The Facebook authorization endpoint returns a redirect to www.facebook.com. This verifies provider initiation, not a completed physical-device login.

Meta app ID: `1803214744845145`. Its Facebook Login use case includes email and public_profile, with the exact Supabase callback above saved in Valid OAuth Redirect URIs. The App Secret is stored only in Supabase provider settings and is never included in this repository or APK.

Meta app publication remains incomplete: business verification, app review, app icon, privacy policy, data-deletion instructions and category require completion. Do not advertise unrestricted Facebook sign-in until Meta approves the production setup. Google Cloud credentials also remain pending.

For device verification, install 0.13.1, open Facebook sign-in using an authorized Meta app-role account, accept the sign-in, check that the app returns to the saved account, then restart and sign out. No claim of completed device verification is made by the widget tests.
