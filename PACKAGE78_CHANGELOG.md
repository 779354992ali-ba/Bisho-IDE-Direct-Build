# Package78 — Local build preflight hardening

## Scope
- Added a fail-closed local-build environment model with explicit device support, runtime verification, required storage, and missing-requirement details.
- Android preflight checks ABI (`arm64-v8a`), Android 10 or newer, and at least 12 GiB free in the app-private files partition.
- Added validation for a future engine manifest (schema version, ABI, launcher, Flutter executable, Java executable, and Android SDK directory).
- Canonical path checks reject manifest paths that escape the app's private engine directory.
- The build screen now shows device eligibility, storage target, toolchain-file state, and missing prerequisites.
- Added tests for spoofed readiness flags and prerequisite reporting.

## Safety and truthfulness
- `runtimeVerified` is always false in this package.
- `canBuildLocally` is always false in the Android bridge.
- A manifest or executable files are not evidence that Linux Flutter/Gradle tools can execute on Android.
- No APK build, Flutter test, Dart analysis, or on-device runtime test was performed in this environment.
- GitHub Actions cloud building is unchanged and is not described as local building.

## Requirements for a later real local-build milestone
A signed and versioned Android-compatible Linux runtime, Flutter SDK, JDK, Android SDK/build-tools, process execution strategy compatible with Android app sandboxing, cancellation/progress/log streaming, and a successful end-to-end APK build on a physical device are still required.
