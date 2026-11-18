# Package91 — Local Build Engine Foundation

## Changes in this iteration
- Reduced the local-build free-space admission floor from 5 GiB to 2.5 GiB. This is a minimum admission threshold, not a promise that every project fits; Gradle caches, SDK contents and project size can require substantially more.
- Kept the fail-closed rule: local build remains disabled until a device-side Debug APK build has been completed and its signature/alignment evidence is validated.
- Exposed Release/AOT verification as a separate state in the Dart environment model and UI; Debug success is not presented as Release success.
- Kept GitHub Actions as the fallback route.

## Not yet implemented / not certified
- Alpine minirootfs download and safe tar.gz extraction are not yet connected to the app.
- A compatible PRoot ARM64 runtime is not bundled or verified.
- Flutter, JDK and Android SDK ARM64 toolchain bundle is not bundled.
- Offline readiness is not claimed until all toolchain packages and project dependencies are cached.
- No on-device build, Dart analysis, Kotlin compilation, or GitHub Actions build has been run for this iteration.

## Alpine source selected for the next bootstrap stage
Official Alpine 3.24.4 aarch64 minirootfs archive (about 4 MB):
https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-3.24.4-aarch64.tar.gz
Official SHA-256 sidecar:
https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-3.24.4-aarch64.tar.gz.sha256

The sidecar must be fetched over HTTPS and checked against the downloaded archive before extraction. The existing ZIP-only installer must not be used for this tar.gz archive.
