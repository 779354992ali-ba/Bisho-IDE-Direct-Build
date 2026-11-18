# Bisho IDE Package 96 — GitHub APK Artifact Download

## What changed

- Added an in-app GitHub Actions Artifact download path for a successful workflow run.
- Bisho IDE now lists artifacts for the exact run ID, selects the non-expired `Bisho-IDE-Release-APK` artifact, downloads its ZIP, extracts only `app-release.apk`, and saves it into the currently selected project folder through Android Storage Access Framework.
- Added strict bounds for the downloaded artifact (250 MiB) and extracted APK (150 MiB).
- Requires a valid `SHA256SUMS.txt` entry for `app-release.apk` and verifies SHA-256 before saving. Missing or mismatched checksums stop the operation.
- Added the direct `crypto` dependency and incremented Android app version code to 96.

## User flow

1. Open a Flutter project in Bisho IDE.
2. Connect GitHub and upload the project, or enter an existing `owner/repo`.
3. Dispatch the configured workflow and refresh its status.
4. After the run concludes with `success`, use **Download APK to project folder**.
5. The APK is saved as `app-release.apk` in the selected project folder.

## Required workflow contract

The workflow must upload an Actions artifact named `Bisho-IDE-Release-APK` containing:
- `app-release.apk`
- `SHA256SUMS.txt`, with a SHA-256 line referencing `app-release.apk`.

The existing `.github/workflows/main.yml` produces this artifact and checksum file.

## Validation status

- Archive extraction and source-level consistency checks: performed for this package.
- Flutter format/analyze/tests and Android APK build: **not run**; this execution environment has no Flutter/Dart SDK or Android SDK.
- Device verification on Samsung Android: **not run**.
- This package improves the remote build/download workflow. It does **not** claim that the ARM64 local offline Flutter Android toolchain or PRoot runtime is complete.
