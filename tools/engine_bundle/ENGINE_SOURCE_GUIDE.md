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
- Current native installer admission is dynamic: after download it requires 1 GiB free; extraction stops before using the final 512 MiB reserve; the archive and expanded payload are capped at 8 GiB and 12 GiB respectively. Once installed, the current native build preflight requires 2.5 GiB free as a starting reserve, not a guarantee for every project. Keep this aligned with `MainActivity.kt`; do not reintroduce the obsolete 20 GB / 5 GB gates.
- Gradle worker count and JVM heap are bounded for mobile devices. These settings improve predictability but do not guarantee that every device has sufficient RAM for every Flutter project.


## Package100 pinned source observations

- Flutter reference installer repository: `0xR0/arm64-flutter-setup`, observed commit `6a6eb5e13ce99d99e5604b6be83ecb46b3098e02`; its documented baseline is Flutter tag `3.27.4` / Dart `3.6.2`. The helper repository is unsigned and is a compatibility reference, not a trusted binary distribution. Do not pipe its moving `master` installer into a production build.
- ARM64 Android PRoot: upstream `proot-me/proot` tag `v5.5.0`, built with Android NDK `29.0.14206865` for `aarch64-linux-android24`. Package100 CI successfully built an Android ELF with interpreter `/system/bin/linker64`; observed binary SHA-256 from CI run `44874583756` (build commit `5521e9cfb6387420ff600336ab382cea08a115b2`): `a9dc2a7ab6ce65e2a1f8a832990b07cd097ee9ef57c65ffc7701617c33fa300e`. The build pins PRoot commit `25dc6a3134891f98a79f57ce1c2c1b23ff15cad1`, Talloc 2.5.0 source archive SHA-256 `912afa237510ae542a7733998eb18a12bcda35ab6729c8e2ddb43e8d0ebab007`, NDK `29.0.14206865`, and target `aarch64-linux-android24`. New CI artifacts record these inputs in `BUILD_PROVENANCE.txt` and checksum the provenance and license files as well as the binary.
- Commit451 ARM64 Build Tools release `platform-tools-35.0.1` (2026-05-21) published these SHA-256 values:
  - `aapt2`: `c57d02d2986d7d68147d74525ad8a5fbb105f12723b33f1ce9eab12acd238cf0`
  - `aidl`: `9ae2dfac8ff49f34d493c2fd3d96f6153563f2ec0f07d18f6f661d0e8403d6a2`
  - `zipalign`: `d0688e26a0960b010c9702c4a4f6e53308d239a618b1dd0e5d0f4c5ad1c84fe6`
  - `split-select`: `172ecf6c4e93cc6f80a544f48b9a8fe770dd67f83b2f277504291cb4d1b82e3e`
  - combined archive: `a6a8d0fbc40bf42dddd88ebd336c4f5c71d638dbd760e239fff93c15445ecc84`
- These pinned hashes make provisioning reproducible, but do not by themselves certify that the tools run together inside Bisho's final guest rootfs. The complete Debug smoke build and phone probe remain mandatory.
- Android SDK license acceptance must be performed by the publisher/user after reviewing and accepting the applicable terms. Package100 does not fabricate or silently insert an acceptance file.
