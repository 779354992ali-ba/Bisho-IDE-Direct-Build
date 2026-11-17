# Package84 Static Validation Report

Date: 2026-11-17

## Passed
- `bash -n tools/engine_bundle/validate_and_pack.sh` — shell syntax valid.
- `pubspec.yaml` parsed successfully with PyYAML; version is `1.0.0+84`.
- `android/app/src/main/AndroidManifest.xml` parsed successfully as XML.
- Kotlin parser pass via `kotlinc` emitted no `expecting`, `unexpected tokens`, or syntax-error diagnostics.
- Package archive integrity checked after ZIP creation.

## Not run / cannot be claimed
- Flutter/Dart SDK is not installed in this build environment, so `flutter analyze`, `flutter test`, and Dart formatting were not run.
- Android SDK/Gradle Android classpath is not available, so `assembleDebug`, Kotlin Android compilation, and APK packaging were not run. The standalone `kotlinc` attempt reports unresolved Android/Flutter symbols because those dependencies are absent; it is not an Android compile.
- No ARM64 PRoot runtime bundle is present in this environment, so the new in-app engine probe and the bundle packer were not executed against a real rootfs.
- No Debug or Release APK was produced here. Real-phone end-to-end validation remains required.

## Acceptance criteria for the next device test
1. Install a separately verified ARM64 runtime bundle.
2. Run **اختبار تشغيل المحرك فعليًا** and confirm PRoot, Flutter, Java, sdkmanager and native build tools execute.
3. Build a clean Flutter project as Debug inside Bisho IDE.
4. Confirm `apksigner verify` and `zipalign -c -v 4` both pass.
5. Save the APK through SAF and install it on the same phone.
6. Test Release separately; it is not accepted unless the Android ARM64 Linux `gen_snapshot` tool is present and the Release APK passes verification.
