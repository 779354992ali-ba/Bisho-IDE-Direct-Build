# Bisho IDE Package92 — Local Build Engine Progress

## Changes in this package

- Corrected the Flutter-side Release/AOT status mapping: `releaseBuildVerified` is now read from the native `releaseBuildVerified` field instead of being inferred from `runtimeVerified`.
- Native diagnostics now explicitly publish `releaseBuildVerified`, derived from the persisted Release APK proof record.
- The fallback diagnostic response explicitly marks Release verification as false.
- Added a regression test proving that a verified Debug build does not imply Release/AOT verification.
- Kept local build readiness fail-closed: a valid installed toolchain and a successful device-side Debug APK smoke build remain required.

## Bootstrap research and important compatibility decision

- Alpine 3.24.4 aarch64 Mini RootFS is published by the official Alpine mirror at:
  `https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-3.24.4-aarch64.tar.gz`
- The official directory publishes `.sha256`, `.sha512`, and `.asc` sidecars. The app must fetch and validate the checksum sidecar (or use a pinned digest) before extracting the archive.
- The current native engine installer accepts ZIP only. It does not yet accept a `.tar.gz` Alpine rootfs; feeding the Alpine archive to it is invalid.
- PRoot is a separate executable/runtime, not part of Alpine. The official `proot-me/proot` project documents Android/community packaging separately; ARM64 prebuilt packages found in community repositories have distinct licenses and provenance. No third-party binary has been silently copied into this package.
- Some Android SDK components and Android build-tools are not published as native Linux ARM64 binaries. A complete on-device Flutter Android toolchain therefore needs an ARM64-compatible packaging strategy and real device validation, not merely `apk add` inside Alpine.

## Not claimed as complete

This package does not yet contain a bundled PRoot ARM64 executable, Alpine tar extractor/bootstrap, Flutter SDK, JDK, Android SDK, or offline dependency cache. It has not been built into an APK or tested on a physical Android device in this environment. The local build feature remains disabled until its existing native smoke-build proof is generated on the target device.
