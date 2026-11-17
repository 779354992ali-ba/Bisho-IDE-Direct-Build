# Package79 — Local Build Execution Bridge

## Added
- SAF project staging into the app-private support directory, with bounded depth, file count, and total copied bytes.
- Android MethodChannel entry points for starting and cancelling a local build.
- EventChannel stream for native build output and error lines.
- App-private path validation before invoking the embedded Linux launcher.
- APK existence/size verification and copy-back to the selected project folder as `app-release.apk`.
- Best-effort removal of the temporary staged project after the operation.

## Embedded runtime contract
The app expects a runtime bundle under `files/bisho-local-build-engine/` and a JSON manifest named `engine-manifest.json` with:

```json
{
  "schemaVersion": 1,
  "abi": "arm64-v8a",
  "runtimeLauncher": "runtime/proot",
  "rootfsDirectory": "rootfs",
  "flutterExecutable": "rootfs/opt/flutter/bin/flutter",
  "javaExecutable": "rootfs/opt/jdk/bin/java",
  "javaHome": "/opt/jdk",
  "androidSdkDirectory": "rootfs/opt/android-sdk",
  "androidSdkPath": "/opt/android-sdk"
}
```

The launcher is expected to support the PRoot-compatible arguments used by the native bridge (`-0 -r ROOTFS -w PROJECT /bin/sh -lc COMMAND`). The rootfs must contain a compatible Linux userspace, Flutter SDK, JDK 17, Android command-line tools, platform-tools, and the Android platform/build-tools required by the target Flutter project.

## Important limitation
This package implements the staging, execution bridge, cancellation, progress, and artifact-return path. It does **not** ship the multi-gigabyte Linux/Flutter/JDK/Android SDK runtime bundle and does not claim that local APK builds work on a user's phone yet. The local build button remains unavailable until a matching runtime bundle is installed and the environment probe confirms its required files. `runtimeVerified` deliberately remains false pending an end-to-end on-device APK build.

## Verification
- Source-level inspection and ZIP integrity checks only.
- Flutter analyze/tests and Android compilation were not run because Flutter/Dart/Android SDK are unavailable in this environment.
