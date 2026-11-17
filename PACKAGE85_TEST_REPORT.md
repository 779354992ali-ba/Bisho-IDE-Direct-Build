# Package85 Static Validation Report

Date: 2026-11-17

## Changes inspected
- Android SAF project staging now streams through `ContentResolver` into app-private storage.
- Dart delegates staging through the existing local-build MethodChannel and validates the returned directory.
- Build and artifact verification paths from Package84 remain in place.

## Checks to run in this environment
- ZIP archive integrity.
- `pubspec.yaml` parse and version check.
- Android manifest XML parse.
- Engine bundle packer shell syntax.
- Kotlin parser diagnostics scan (Android/Flutter symbols remain unresolved without Android and Flutter classpaths).

## Not run / cannot be claimed
- Flutter/Dart SDK is not installed: no `flutter analyze`, `dart analyze`, `flutter test`, or Dart formatter run.
- Android SDK / Gradle Android classpath is not installed: no `assembleDebug`, Kotlin Android compile, or APK build.
- SAF staging requires Android's DocumentsProvider and a real device; it was not executed in this container.
- No PRoot runtime bundle was supplied; no real local Flutter build was run.

## Device acceptance test
1. Install Package85 on an ARM64 Android device.
2. Grant Bisho IDE access to a Flutter project folder through SAF.
3. Run local Debug build and confirm staging progress appears without Dart heap spikes.
4. Cancel during staging and confirm partial staged files are deleted.
5. Re-run staging, build Debug, verify signature and ZIP alignment, save APK via SAF, and install it.
6. Test Release separately only when the installed Flutter SDK includes a working ARM64 Android `gen_snapshot`.
