# Bisho IDE Package 97 — GitHub Build Pipeline

Package97 continues the Package96 in-app GitHub Actions artifact download flow and standardizes the build toolchain on Flutter 3.47.9.

## Build flow

1. Open or upload a Flutter project to the GitHub repository from Bisho IDE.
2. Select `main.yml`, branch `main`, and Flutter `3.47.9`.
3. Dispatch the workflow and wait for the run to finish successfully.
4. Download `Bisho-IDE-Release-APK` from the completed run into the selected project folder.
5. Bisho IDE validates `SHA256SUMS.txt` before saving `app-release.apk`.

The workflow runs Android preflight, `flutter analyze`, `flutter test`, and `flutter build apk --release`. It publishes the APK, SHA-256 checksum, and build metadata as one artifact.

## Honest verification status

The package was statically checked and its ZIP integrity is verified. No GitHub Actions run was started because the linked GitHub integration did not expose the target repository during this session. Flutter/Dart/Android SDK are not installed in this execution environment, so this package is not represented as a successful APK build until GitHub Actions reports success.
