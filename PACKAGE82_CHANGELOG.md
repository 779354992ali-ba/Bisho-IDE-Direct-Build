# Bisho IDE Package 82 — Local Build Reliability

## Implemented

- Fixed the engine installer storage preflight: the downloaded archive is now counted toward the 20 GB installation budget, rather than requiring another 20 GB after download.
- Hardened runtime manifest path handling. Paths must be clean relative paths inside the extracted engine; absolute paths, traversal segments, backslashes and unsafe guest-path characters are rejected.
- Strengthened engine archive validation: launcher, root filesystem, Flutter, Java and SDK must have the expected file/directory types; the Linux root filesystem must contain an executable `/bin/sh`.
- Added a mandatory `engine-executables.txt` bundle manifest. The installer validates each listed path and restores Unix executable permissions after ZIP extraction, which otherwise does not preserve those mode bits.
- Corrected `JAVA_HOME` derivation from the Java executable path.
- Added a persistent app-private build home for Pub and Gradle caches so dependencies/cache are not written into the runtime image.
- Added PRoot binds for `/dev` and `/proc` when available.
- Added explicit Flutter, Java, SDK, AAPT2 and AIDL preflight commands before dependency resolution and APK compilation.
- Configured Gradle's `android.aapt2FromMavenOverride` to use the bundled ARM64-native AAPT2 instead of an incompatible host binary.
- Added explicit Debug/Release APK selection. Debug is the default for ARM64 local testing; Release first checks for Flutter's Android ARM64 Linux-host `gen_snapshot` artifact and stops with a clear message if it is absent.
- Both build modes target `android-arm64` and verify the generated APK signature with `apksigner` before returning it.
- Only a successful Release APK build writes the runtime verification marker. A successful Debug build does not falsely certify Release/AOT support.
- Engine validation requires Android SDK command-line tools and executable `aapt2`, `aidl`, `zipalign`, `split-select`, and `apksigner` build-tools. The installer restores executable permissions for these known tools after extraction.
- Shell-facing guest paths are constrained to a safe character set and quoted before use.
- SAF APK temporary filenames no longer start with a dot, improving compatibility with document providers that reject hidden names.
- Installer cancellation is exposed only during HTTPS download; the UI no longer presents a misleading cancel action during native verification/extraction.
- Bumped app version to `1.0.0+82`.

## Not yet achieved / must not be represented as complete

- No verified ARM64 PRoot + Linux rootfs + Flutter + JDK 17 + Android SDK runtime archive is included in this source package.
- No trusted download URL or independently published SHA-256 is configured.
- No Flutter/Dart SDK, Android SDK or device runtime is available in the development container, so Flutter analysis/tests and a real Android build were not run here.
- End-to-end local APK build and installation still require testing on the target Android phone with a real compatible engine bundle.
- ARM64 Flutter Release/AOT support depends on the presence of Flutter's Android ARM64 Linux-host `gen_snapshot`; a Debug APK build does not establish Release readiness.
