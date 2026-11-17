# Bisho IDE Package79

Package79 adds the local-build execution bridge: bounded SAF-to-private-storage staging, native Android process orchestration through an embedded Linux launcher, live output events, cancellation, APK verification, and copy-back to the project folder.

The actual Linux/Flutter/JDK/Android SDK runtime bundle is not included. Local building is therefore not represented as working until that bundle is installed and a real on-device APK build succeeds. GitHub Actions remains a separate cloud-build path.

See `PACKAGE79_LOCAL_BUILD_RUNNER.md` for the runtime manifest contract and limitations.
