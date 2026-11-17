# Bisho IDE Package89 — In-app real Debug build certification

## Main change

The in-app engine probe no longer treats successful `--version` calls and tool presence as sufficient evidence that the local Android build pipeline works. It now creates a disposable Flutter Android project inside the installed PRoot rootfs, resolves its Flutter packages, runs a real `flutter build apk --debug --target-platform android-arm64`, and verifies the produced APK with the selected ARM64 `apksigner` and `zipalign` tools.

## Proof and readiness

- The smoke APK is copied to app-private artifact storage using bounded streaming I/O.
- A Debug verification record is written atomically and binds the proof to the device ABI, installed engine manifest SHA-256, APK path, APK byte count, and APK SHA-256.
- The existing environment inspector validates this proof before it reports local Debug build readiness.
- Release remains separate and is not certified by the Debug smoke test.
- The probe has a 60-minute ceiling to allow first-run Gradle distribution and Android dependency downloads. It uses the persistent Gradle/Pub cache also used by project builds.
- The smoke workspace is disposable and removed after the probe. The verified APK is retained under the app-private artifacts directory.

## Validation limits

- ZIP integrity, YAML/XML/JSON parsing, shell syntax, and Kotlin parser-level syntax checks were run for this package.
- This environment does not provide Flutter, Android SDK, Android Gradle dependencies, or an Android device. Therefore no real PRoot smoke build or APK was run here. The new in-app probe is the mechanism that will perform that end-to-end test on the user's device after a compatible engine bundle is installed.
