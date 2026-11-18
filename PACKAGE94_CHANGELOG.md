# Package94 — Alpine TAR.GZ installer and PRoot build lane

## Implemented in source
- Added a separate Android method-channel action `installAlpineRootfs`; it does
  not route TAR.GZ files through the ZIP engine installer.
- Added Apache Commons Compress TAR/GZIP reading, SHA-256 verification,
  bounded entry/expanded-size checks, duplicate/path traversal rejection,
  deferred symlink/hardlink creation, executable mode restoration, required
  rootfs-file checks, and staged activation with rollback.
- Added `AlpineRootfsInstaller` which downloads the pinned official Alpine
  3.24.4 aarch64 archive and its official SHA-256 sidecar over HTTPS, parses
  the exact archive digest, then invokes native verification/extraction.
- Added an upstream PRoot v5.5.0 Android ARM64 NDK cross-build workflow with
  provenance and SHA-256 artifact output.

## Not certified / remaining
- The Android Gradle build has not been run here; dependency resolution and
  Kotlin compilation must be checked by CI.
- The PRoot workflow has not yet been run, and no PRoot executable is bundled.
- Alpine extraction has not been exercised on a physical Android device.
- Alpine alone is not a complete Flutter Android build host. Flutter, JDK,
  Android SDK/build-tools, ARM64 host tools, Flutter artifacts, pub packages,
  Gradle distributions/dependencies and Android licenses are not yet bundled.
- Offline readiness requires a full offline Debug build (and separately a
  Release/AOT build) after disabling network access. No such proof exists.
- PRoot requires ptrace behavior permitted by the device kernel/security policy.

## Integrity notes
The app obtains the SHA-256 digest from Alpine's official sidecar at install
 time rather than embedding an unverified digest in source. The digest is
checked natively against the downloaded bytes before any extraction begins.
