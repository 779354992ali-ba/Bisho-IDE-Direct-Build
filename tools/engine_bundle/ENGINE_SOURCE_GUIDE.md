# ARM64 engine preparation notes

This is a source and compatibility guide for preparing a runtime outside the app before creating a Bisho engine ZIP. It is not a downloadable engine archive.

## Known ARM64 Debug reference stack

A public Termux + Ubuntu PRoot setup reports a working Flutter Android **Debug** build on ARM64 with:

- Flutter 3.27.4 / Dart 3.6.2
- OpenJDK 17
- Android API 35 and Build Tools 35.0.1
- ARM64 replacements for `aapt2`, `aidl`, `zipalign`, and `split-select`
- PRoot + an ARM64 Ubuntu root filesystem

Reference: https://github.com/0xR0/arm64-flutter-setup

## Native Android build tools

The normal Linux Android SDK packages include x86-64 native host binaries. An ARM64 guest needs ARM64 builds of the native tools. One community source publishes drop-in Linux ARM64 versions of `aapt2`, `aidl`, `zipalign`, and `split-select`:

https://github.com/Commit451/android-arm-build-tools

Use a pinned release, verify its published checksums, inspect its license, and run each binary inside the exact guest rootfs before packaging. Do not use a moving `latest` URL or accept an unverified checksum in a production engine installer.

## Flutter Release limitation

The reference ARM64 setup reports Debug builds working while Android Release/AOT is blocked by the missing Linux ARM64 Android `gen_snapshot` host artifact. Flutter issue #189724 describes the same missing artifact on a Linux ARM64 host. Therefore:

- Debug can be enabled only after a real Debug APK is built, signature-verified and zip-aligned on the phone.
- Release must remain unavailable until the exact `android-arm64-release/linux-arm64/gen_snapshot` tool exists, executes, and a Release APK passes the same artifact checks.
- A generic Linux ARM64 `gen_snapshot` is not interchangeable with the Android AOT snapshot generator.

Reference: https://github.com/flutter/flutter/issues/189724

## Packaging

After provisioning the complete rootfs, run:

```bash
./tools/engine_bundle/validate_and_pack.sh /path/to/runtime-root /path/to/bisho-engine-arm64.zip
```

The script expects the fixed directory layout documented in `PACKAGE82_RUNTIME_BUNDLE_SPEC.md`, executes the tools through PRoot, dereferences symlinks into the archive, writes the engine manifest and executable inventory, and prints the final SHA-256. The ZIP must then be tested by installing it into Bisho IDE on a real supported phone.

## Package86 packaging requirements

- Include a non-empty `rootfs/opt/android-sdk/licenses/android-sdk-license` file after the Android SDK licenses have been accepted on the ARM64 provisioning host.
- The packer and app select the newest complete Build Tools version by version sort (`sort -Vr`); keep `aapt2`, `aidl`, `zipalign`, `split-select`, and `apksigner` together in that selected version directory.
- Package86 retains the last three Debug and Release APKs separately from the temporary staged project and validates their SHA-256 against the build-proof record. Removing or changing a retained APK invalidates the corresponding proof.
- Engine installation still requires 20 GB free. Once installed, the app requires at least 5 GB free for a build workspace and Gradle caches.
- Gradle worker count and JVM heap are bounded for mobile devices. These settings improve predictability but do not guarantee that every device has sufficient RAM for every Flutter project.
