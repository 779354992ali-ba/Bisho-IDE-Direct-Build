# Package86 — Persistent verified artifacts and mobile build reliability

## Implemented

- Retain a verified APK in app-private storage outside the temporary staged project. The Flutter preview screen can now delete its staged project without invalidating the device's build proof.
- Tie Debug and Release verification records to the exact retained APK path, byte length, SHA-256, device ABI, and installed engine-manifest SHA-256. Missing, changed, or replaced APKs no longer count as a successful build.
- Keep the newest three retained APKs per build mode to limit private-storage growth.
- Allow the SAF exporter to copy only APKs from the two app-private build/artifact roots.
- Move environment inspection to the native build executor so hashing retained APKs does not run on Android's UI thread.
- Separate engine installation storage (20 GB) from post-install build workspace storage (5 GB). An installed engine no longer makes the app report the device unsupported merely because extraction consumed the initial 20 GB reserve.
- Keep the installer preflight tied to the full engine-install budget, even when an engine is already installed.
- Add build-time free-space checks, bounded Gradle worker count/JVM memory, stable Gradle caching, Flutter analytics suppression, and avoid a redundant Pub resolution during `flutter build`.
- Select the newest complete Android Build Tools version using version sorting consistently for build and APK verification.
- Expand the engine probe with Flutter doctor diagnostics and a longer bounded timeout.
- Require the Android SDK license acceptance file in the engine packer and record the selected Build Tools version in the generated manifest.

## Not claimed

- No ARM64 PRoot/RootFS/Flutter/JDK/Android SDK engine archive was available to bundle in this environment.
- No Flutter SDK, Android SDK, Gradle Android classpath, or physical Android device is available here. Flutter analyze/tests, Android compilation, and end-to-end APK production were not run.
- Debug and Release remain unverified until a real engine bundle is installed and builds are completed on a supported phone.
