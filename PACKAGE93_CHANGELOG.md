# Bisho IDE Package93 — Release proof and Alpine bootstrap contract

## Implemented

- Native diagnostics now compute a dedicated `releaseBuildVerified` value from the persisted Release APK proof record and return that exact value. The older `runtimeVerified` field remains as a compatibility alias only.
- Release status messaging now consumes the explicit Release proof variable.
- Added a pinned Alpine 3.24.4 aarch64 bootstrap descriptor with official archive, checksum-sidecar, and signature URLs.
- Documented the required safe TAR.GZ extraction contract and the boundary between Alpine bootstrap and the separate Flutter/Java/Android toolchain.

## Not implemented / not verified

- No TAR.GZ extraction has been added to Android yet; the current engine installer still accepts ZIP archives only.
- No PRoot binary is bundled. Upstream PRoot is GPL-2.0-or-later; its current documentation points to source and CI artifacts rather than a stable official Android ARM64 release asset. A third-party Android build exists, but must undergo source, license, checksum, and device verification before adoption.
- No Flutter SDK, JDK, Android SDK/build-tools, or offline dependency cache is bundled.
- No APK build or physical-device test was run for Package93 in this environment.

## PRoot source decision

The preferred path is to build PRoot from the upstream `proot-me/proot` source for Android ARM64 using a pinned Android NDK toolchain, retain the exact source commit and build logs, publish a SHA-256 sidecar, and include the GPL notices/source offer. Do not download an unpinned community binary as a production dependency.

## Build architecture caveat

Alpine aarch64 uses musl. Android SDK build tools and Flutter's Linux Android artifacts must be checked individually for ABI and libc compatibility. The Android app must not report a ready local build environment until the device successfully executes a complete Debug APK build; Release/AOT must have its own independent proof record.
