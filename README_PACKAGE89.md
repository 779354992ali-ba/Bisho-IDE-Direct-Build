# Bisho IDE Package89 — end-to-end in-app Debug build test

Package89 upgrades the local engine test from checking tool versions to building a disposable Flutter Android ARM64 Debug APK inside PRoot.

## How to test on the phone

1. Install a certified ARM64 engine bundle using the in-app engine installer.
2. Open the local build section in the Flutter preview screen.
3. Tap **اختبار بناء APK تجريبي فعليًا**.
4. Keep the app open while Flutter precache, Pub, Gradle, and Android build dependencies are prepared. First run can take up to 60 minutes.
5. Read the live build log. A successful result means the smoke APK was produced, verified by `apksigner`, checked by `zipalign`, retained in app-private storage, and bound to a SHA-256 verification record.

The test certifies Debug only. Release/AOT is still independent and must pass a full Release build and APK verification.

This source package does not contain the large runtime bundle. The engine must be provisioned on a Linux ARM64 host and packaged using `tools/engine_bundle/validate_and_pack.sh`.
