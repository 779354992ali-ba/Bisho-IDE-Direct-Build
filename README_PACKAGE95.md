# Bisho IDE Package95 — Alpine UI connection and toolchain readiness gate

## Implemented
- Connected the Alpine ARM64 installer to the Flutter Preview local-build panel.
- Added progress display and a cancel action for Alpine archive download.
- Added a preflight free-space check before starting the download.
- Added `alpineRootfsInstalled` to native environment inspection and Flutter model/UI.
- Added a regression test: Alpine is never reported installed when native inspection does not return a positive result.
- Added an explicit ARM64 toolchain bootstrap contract for Flutter 3.47.9, Java 17, Android API 36 / Build Tools 36.0.0, required host tools, offline caches, and proof requirements.

## Not completed / not certified
- PRoot ARM64 build workflow has not been dispatched or run. No PRoot executable has been produced, verified, or integrated.
- The existing PRoot workflow is a draft lane. Its host `libtalloc-dev` package is not an Android ARM64 target dependency; the workflow must not be treated as a successful Android build recipe until target talloc is cross-built and linked.
- Flutter/JDK/Android SDK are not downloaded or installed by this package.
- ARM64 replacements for Android SDK native host tools are not packaged. Google SDK Linux host binaries are not assumed to execute on Linux ARM64.
- Pub, Gradle, Flutter engine artifacts, SDK platforms/build-tools and licenses are not cached offline.
- No Flutter/Dart executable or Android SDK is available in the editing environment; Flutter tests, Gradle/Kotlin build, APK build, and physical-device tests were not run.
- Alpine install UI is connected to the native extraction method, but extraction still needs testing on the user's Android device. PRoot is not yet invoked against Alpine.

## Acceptance gates
1. CI compiles Android/Kotlin sources and Flutter tests pass.
2. Install Alpine on an ARM64 Android phone; verify `/etc/alpine-release`, symlinks, executable modes, and `/bin/sh` under PRoot.
3. Build PRoot from upstream source with Android-target `libtalloc`, retain commit, license, build logs, and SHA-256; verify ELF interpreter/ABI and `--version` on device.
4. Install Flutter/JDK/SDK and ARM64 host-tool replacements from pinned sources with vendor checksums/signatures.
5. Complete an online provisioning pass and cache Flutter, Pub, Gradle and SDK dependencies.
6. Disable network access and build a real Debug APK; verify signature and zip alignment. Only then mark Debug offline-ready.
7. Separately prove Release/AOT; do not infer it from Debug.
