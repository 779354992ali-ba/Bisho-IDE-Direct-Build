# Bisho IDE Package81 — Large Artifact & Runtime Path Hardening

## Changes
- APK export from the local builder now streams directly from app-private storage to the selected Android Storage Access Framework folder in 1 MiB chunks. Dart no longer reads the complete APK into RAM.
- The destination APK is first written under a temporary name and renamed only after the copied byte count matches the source file size; a previous APK is retained until the new copy has finished.
- Native artifact export validates that the source APK is inside Bisho IDE's private build staging directory and rejects invalid destination names and non-tree SAF URIs.
- The local build command now derives Flutter, Java, and Android SDK guest paths from the validated manifest paths instead of assuming `/opt/...` locations.
- The verification marker is written through a temporary file and renamed after a successful release APK build.
- Environment inspection reads the verification marker once and checks executable permissions for Flutter and Java.
- Engine installer now performs the 20 GB storage preflight before downloading, blocks concurrent installs, rejects credential-bearing or fragment URLs, and sends an explicit archive Accept header.
- App version updated to `1.0.0+81`.

## Validation status
- Source-level checks and ZIP integrity checks were performed.
- Flutter/Dart SDK and Android Gradle toolchain are not available in this environment; `flutter analyze`, tests, Kotlin/Android compilation, and on-device APK build were not run.
- The embedded PRoot/Linux/Flutter/JDK/Android SDK runtime archive is still not included or published by this package. Local build remains conditional on installing a trusted compatible runtime and successfully producing a real APK on the target device.
