# Naadh (alien_reader_app)

Android app for the Naadh reader: pairs with the reader (a Raspberry Pi with
a camera), captures pages, and reads them aloud with an AI summary. Signing
in uses the Naadh cloud API.

## Requirements

- Flutter 3.47 (stable) with Dart 3
- Android SDK (compile/target SDK 36, min SDK 24) and JDK 17+
  (Android Studio's bundled JBR works)
- An Android phone for anything involving the reader (camera, Wi-Fi setup,
  on-phone OCR and speech)

## First-time setup

1. `flutter pub get`
2. Create **`dart_defines.json`** in the project root (it is gitignored):

   ```sh
   cp dart_defines.example.json dart_defines.json
   ```

   | Key | Meaning |
   |---|---|
   | `NAADH_API_BASE_URL` | Naadh cloud API, e.g. `https://alien-reader-cloud-api.onrender.com`. **Required:** without it the app builds but cannot sign in. |
   | `NAADH_SETUP_BASE_URL` | The reader's address on its setup hotspot, normally `http://10.42.0.1:8000`. |

   No secrets go in this file. The user's own Gemini key is entered in the
   app (Settings → Processing) and kept in the phone's secure storage.

3. Pass the file to every run and build:

   ```sh
   flutter run --dart-define-from-file=dart_defines.json
   ```

   The VS Code launch config (`.vscode/launch.json`) already does this.

The reader is reached at `http://drpi2copy1.local:8000` on the home Wi-Fi
(`lib/core/constants/pi_config.dart`).

## Builds

| Build | Command | Installs as |
|---|---|---|
| Debug | `flutter build apk --debug --dart-define-from-file=dart_defines.json` | `com.alieninnovations.alien_reader_app.debug` |
| Release | `flutter build apk --release --dart-define-from-file=dart_defines.json` | `com.alieninnovations.alien_reader_app` |
| Play upload | `flutter build appbundle --release --dart-define-from-file=dart_defines.json` | — |

Debug and release use different app IDs so they can be installed side by
side (they are signed with different keys and cannot replace each other).

Do not use `--split-per-abi` for builds you install on a test phone: those
get a higher version code, and later `flutter test` runs then uninstall the
app (wiping its data) to install over it.

### Release signing

Release builds are signed with the **upload key**, which never goes in the
repo. Gradle reads its details from a `key.properties` file outside the
repo:

- `NAADH_KEY_PROPERTIES` (environment variable with the file's path), else
- `~/.naadh-release/key.properties` (on Windows,
  `C:\Users\<you>\.naadh-release\key.properties`)

```properties
storeFile=C:/Users/<you>/.naadh-release/upload-keystore.jks
storePassword=<keystore password>
keyAlias=upload
keyPassword=<key password>
```

Without that file a release build still completes, but it is signed with
the debug key (Gradle prints a warning) and cannot be uploaded to Play. Ask
the project owner for the keystore; keep a backup of it off this machine.

Release builds are shrunk by R8. `android/app/proguard-rules.pro` holds the
rules this app needs (ML Kit's optional language models, and the classes
`shared_preferences` reaches over JNI); without them the release build
fails or crashes at launch.

## Tests

```sh
flutter analyze
flutter test
```

On-device tests live in `integration_test/` and run against a real phone
(and, for most, a real reader on the same network):

```sh
flutter test integration_test/<file>.dart -d <device-id> --no-uninstall \
  --dart-define-from-file=dart_defines.json
```

`--no-uninstall` keeps the phone's sign-in and data. A test run leaves a
test build installed in place of the debug app; reinstall the normal debug
APK afterwards.

## Repository

- `origin`: https://github.com/abhinava01810/alien-reader (`main` is current)
- `upstream-original`: the repo this project was first copied from; fetch
  only, pushes are disabled.
