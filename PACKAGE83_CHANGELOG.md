# Bisho IDE Package 83 — Runtime Integrity and Build Safety

## Implemented

- Enforced the runtime bundle contract: Flutter, Java and Android SDK paths must resolve inside the declared Linux root filesystem during installation and environment inspection.
- Limited `engine-manifest.json` to 1 MiB before parsing to avoid unbounded memory use from malformed bundles.
- Rejected duplicate ZIP entry names during extraction, in addition to existing zip-slip, entry-count and extracted-size limits.
- Rejected duplicate entries in `engine-executables.txt`.
- Bound the Release verification marker to the SHA-256 of the installed engine manifest. Editing or replacing the manifest invalidates the old verification result.
- Removed the expected APK output before each build so an old APK cannot be mistaken for the output of a new successful build.
- Bumped app version to `1.0.0+83`.

## Validation performed in this package environment

- ZIP archive integrity checked after packaging.
- `pubspec.yaml` parsed and version checked.
- Android manifest XML parsed.
- Kotlin source syntax checked where the installed compiler permits parsing; Android/Flutter symbol resolution and full Gradle compilation require the Android/Flutter toolchains.
- No Flutter analyze/test, Android Gradle build, device execution, or APK build is claimed.

## Remaining release blockers

- A real, trusted ARM64 PRoot + Linux rootfs + Flutter + JDK 17 + Android SDK runtime archive is not included.
- No trusted runtime download URL or independently published SHA-256 is configured.
- Debug and Release builds have not been executed on the target Android phone.
- Release/AOT requires the compatible Android ARM64 Linux-host `gen_snapshot` artifact.
