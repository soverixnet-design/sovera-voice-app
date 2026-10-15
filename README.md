# Sovera — mobile design foundation

Flutter source for Android and iOS. Version 0.1.0 is an **offline UI preview**, not a production voice service.

## Included
- Sculpted gradient icons, layered cards, responsive layouts and safe areas.
- Rooms browser with search and local preview-room creation.
- Voice room layout; take/leave a local seat; select 5/6/9/12 seats and explicitly Save.
- Local room text messages and gift collection preview.
- Moments sample, support cards, guest profile and wallet policy display.
- English interface; no mixed-language strings.
- Android debug APK and iOS simulator GitHub Actions build recipes.

## Build
Install the Flutter stable SDK and Android SDK. From this directory:

```sh
flutter create --platforms=android,ios --org com.sovera --project-name sovera .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

APK output: `build/app/outputs/flutter-apk/app-debug.apk`.
The workflow runs these steps when uploaded to a repository on `main`.
The generated application identifier is `com.sovera.sovera`.

On a Mac with Xcode: `flutter build ios --simulator --debug`.
The simulator build cannot be installed on an iPhone. Physical iPhone distribution requires Apple signing and provisioning, then an IPA/TestFlight build. Android public distribution also needs a release signing key and release build.

## Not connected
Google/OTP/Apple login, real RTC audio, live room state, persisted seat settings, private messages, gifts or wallets, payments, agencies, games, rankings, moderation and admin APIs. No fake live counts or payments are presented. Local preview state resets on app restart. No microphone permission is requested because there is no audio engine in this version.

## Verification status
This package was prepared in an environment without Flutter or Android SDK. Flutter analysis, widget tests and native builds have NOT run here. CI results must pass before distributing an APK. Workflow action versions and dependencies should be pinned/reviewed before production use.

See BACKEND.md before implementing real money or voice flows. The supplied HTML blueprint is a planning reference, not executable backend code.
