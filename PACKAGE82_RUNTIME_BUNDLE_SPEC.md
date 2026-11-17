# Bisho IDE Local Build Engine — Bundle Contract (schema 1)

This document defines the runtime archive expected by the in-app installer. It is a contract, not a claim that a runtime archive is included.

## Archive constraints

- ZIP archive downloaded over HTTPS.
- SHA-256 must be obtained from a trusted, separately published release record.
- Maximum compressed archive: 8 GiB.
- Maximum extracted regular-file data: 12 GiB; maximum entries: 100,000.
- Archive must contain `engine-manifest.json` and `engine-executables.txt` at its root.
- `engine-executables.txt` must list every executable path relative to the ZIP root, one path per line. The installer validates every path and restores execute permissions after extraction. Include PRoot, `/bin/sh`, Flutter, Java, SDK tools, Linux commands/scripts and any required NDK/LLVM executables. The list is limited to 8 MiB and 100,000 entries.
- `abi` must exactly match Android's first supported ABI. The current supported device target is `arm64-v8a`.

## Manifest example

```json
{
  "schemaVersion": 1,
  "abi": "arm64-v8a",
  "runtimeLauncher": "runtime/proot",
  "rootfsDirectory": "rootfs",
  "flutterExecutable": "rootfs/opt/flutter/bin/flutter",
  "javaExecutable": "rootfs/usr/lib/jvm/java-17/bin/java",
  "androidSdkDirectory": "rootfs/opt/android-sdk",
  "debugBuildSupported": false,
  "releaseAotSupported": false
}
```

`debugBuildSupported` and `releaseAotSupported` are certification fields, not user-selected options. The Package88 publisher script writes Debug as `true` only after a real ARM64 Flutter Debug APK smoke build plus signature/alignment checks. It writes Release as `true` only after a full Release/AOT smoke build and the same artifact checks. The example values remain `false`, so the example manifest cannot be installed as a certified runtime.

All paths are relative to the ZIP root. They must not be absolute and must not contain `.` or `..` path segments. Flutter, Java and Android SDK paths must be located inside `rootfsDirectory`.

## Required contents

1. `runtime/proot`: executable Android ARM64-compatible PRoot launcher (not a desktop Linux binary), listed in `engine-executables.txt`.
2. `rootfs/bin/sh`: working shell in the guest root filesystem, listed in `engine-executables.txt`.
3. `rootfs/opt/flutter/bin/flutter`: ARM64 Linux Flutter SDK executable and its complete SDK tree, listed in `engine-executables.txt`.
4. `rootfs/usr/lib/jvm/.../bin/java`: ARM64 Linux JDK 17 runtime and complete supporting libraries, listed in `engine-executables.txt`.
5. Android SDK directory with `platforms/`, `build-tools/`, `platform-tools/`, `licenses/`, and command-line tools at `cmdline-tools/latest/bin/`.
6. ARM64-native executable `aapt2`, `aidl`, `zipalign`, and `split-select` plus the Java-based `apksigner` in a build-tools version directory. Stock x86-64 Linux native tools cannot be assumed to execute in an ARM64 PRoot guest.
7. Android SDK platform/build-tools versions compatible with projects targeting the configured compile SDK. SDK license files must be included/accepted by the bundle publisher in accordance with the applicable license terms.
8. Guest Linux dependencies required by Flutter, Git, Java, Gradle, Android build-tools, certificates and HTTPS package downloads. Include an ARM64-compatible NDK/LLVM host toolchain when the target project's Gradle configuration requires it. Package the runtime with symbolic links dereferenced so the installed ZIP tree contains usable executable files and libraries.

## Runtime acceptance test

A bundle is not accepted as production-ready merely because it extracts. On a real supported phone, Bisho IDE must:

- inspect the manifest and required directory structure;
- execute PRoot and enter the guest root filesystem;
- run `flutter --version` and `java -version` successfully;
- resolve a clean Flutter project's packages over the network;
- build a Debug APK with `flutter build apk --debug --target-platform android-arm64`;
- for Release mode, confirm Flutter has `bin/cache/artifacts/engine/android-arm64-release/linux-arm64/gen_snapshot`, then run `flutter build apk --release --target-platform android-arm64`;
- verify the APK signature with the bundled Android SDK `apksigner`;
- verify the resulting APK exists and is non-empty;
- copy the APK through SAF and install it on the phone.

Only after the real APK build succeeds does the app write its local runtime verification marker. The installer intentionally does not mark a bundle as verified.

## ARM64 Flutter AOT caveat

Flutter Android Release builds require the host-side `gen_snapshot` AOT compiler. Flutter's engine documentation explains that this is a host tool, and the Flutter 3.47.0 release notes list the Linux ARM64 Android `gen_snapshot` addition and its subsequent revert. Therefore, do not assume an ARM64 Linux guest can produce Release APKs from an ordinary stable Flutter SDK. Package 82 checks for the exact required artifact and fails early if it is absent. Debug mode is offered separately and does not certify Release/AOT readiness.

References: https://github.com/flutter/flutter/blob/master/docs/engine/Flutter-engine-operation-in-AOT-Mode.md and https://docs.flutter.dev/release/release-notes/release-notes-3.47.0

## ARM64 Android SDK host-tool requirement (Package84)

Do not copy the stock Google Linux `build-tools` native executables into this ARM64 guest and assume they will run. Google's published Linux SDK host tools are generally x86-64; the four native tools commonly needing ARM64 replacements are `aapt2`, `aidl`, `zipalign`, and `split-select`. Java-based `apksigner` can remain from the SDK package when its JDK dependency is available. The bundle publisher must provide compatible ARM64-native replacements and test them inside the exact rootfs.

A community setup documented a working Termux + Ubuntu PRoot ARM64 **Debug** path using Flutter 3.27.4, JDK 17, Android API 35, and ARM64 replacements for the native build tools. This is a useful engineering reference, not an official Google/Flutter distribution and not a prebuilt Bisho engine archive. See `README_PACKAGE84.md` for source links and caveats.

The Package84 packer script validates and packages an already provisioned runtime; it does not provision the rootfs, download SDK packages, accept licenses, or certify that third-party artifacts may be redistributed.

## Package88 certification rules

The Android installer rejects ZIPs without `debugBuildSupported: true`. Release builds additionally require `releaseAotSupported: true`; the app does not infer Release support from the mere presence of a `gen_snapshot` filename. ZIP extraction rejects canonical-path collisions and non-standard path components. The packer checks the architecture of PRoot, Java, and Flutter's Dart VM before running its smoke build.
