# Bisho IDE Package 80 — Local Build Engine Installer

## What changed
- Added `LocalBuildEngineInstaller`, which downloads a user-supplied HTTPS ZIP to app-private storage using `HttpClient` streaming; it never buffers a multi-GB archive in Dart memory.
- The download requires a known `Content-Length`, rejects non-HTTPS URLs, refuses redirects, caps the archive at 8 GB, checks the received byte count, and removes the temporary archive after completion or failure.
- Added an Android-side installer on a background executor. It verifies SHA-256 with `MessageDigest`, extracts with `ZipInputStream` (bounded entry count and expanded size), rejects absolute/traversal paths, validates the manifest and device ABI, sets executable permissions, and switches the new engine directory into place while preserving/restoring the previous directory on a failed switch.
- Added a Bisho IDE UI action to enter the trusted HTTPS archive URL and independently published SHA-256. It displays download/install progress and refreshes the environment report after installation.
- Bumped app version to `1.0.0+80`.

## Runtime archive contract
The ZIP root must contain `engine-manifest.json` and the paths declared by it. `schemaVersion` must be `1`; `abi` must match the device (currently `arm64-v8a`). Required path keys: `runtimeLauncher`, `rootfsDirectory`, `flutterExecutable`, `javaExecutable`, and `androidSdkDirectory`. See `PACKAGE79_LOCAL_BUILD_RUNNER.md` for the expected PRoot command layout.

## Important limitations
- Package80 does **not** contain the multi-GB PRoot/Linux/Flutter/JDK/Android SDK runtime and does not publish a download URL. The user must obtain a compatible archive and its SHA-256 from a trusted publisher. Never install an archive from an unknown source.
- Installation only confirms archive integrity and expected file layout. It does not prove the toolchain can run. The local-build button remains disabled until a real release APK is produced successfully on that device, which creates the verification marker.
- A successful install is not an APK build. Do not describe local building as available until the on-device build succeeds.
- `flutter analyze`, Flutter tests, Kotlin/Android compilation, and device testing were not run in this environment because Flutter/Dart and the Android build toolchain are unavailable here.

## Storage policy
The device preflight and native installer now require at least 20 GB of free app-volume storage to account for the maximum 8 GB archive and up to 12 GB of extracted runtime. This is a conservative gate; an existing engine may consume additional space during upgrades.
