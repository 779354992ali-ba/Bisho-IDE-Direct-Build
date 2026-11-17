# Package86 Static Validation Report

## Intended checks
- ZIP integrity after packaging.
- YAML parsing and version check.
- Android manifest XML parsing.
- Engine packer shell syntax (`bash -n`).
- Kotlin parser diagnostic scan using the available standalone compiler; unresolved Android/Flutter symbols are expected without their classpaths.
- Review of artifact retention, SHA-256 verification, storage thresholds, and deterministic Build Tools selection.

## Not run / cannot be claimed
- Flutter/Dart SDK is not installed: no `flutter analyze`, `dart analyze`, `flutter test`, or Dart formatting.
- Android SDK/Gradle classpath is unavailable: no Android Kotlin compilation, Gradle build, or APK production.
- No physical device or ARM64 PRoot runtime bundle was supplied; SAF, PRoot execution, Debug build, and Release/AOT build were not tested.

## Required device acceptance
1. Install a separately provisioned ARM64 engine ZIP.
2. Run the engine probe and review Flutter doctor output.
3. Build Debug in Bisho IDE; export the APK; close/remove the staged project; confirm the retained artifact and Debug proof still appear valid.
4. Modify or delete the retained APK and confirm the environment inspector invalidates the old proof.
5. Install the exported APK on the device.
6. Run Release separately only when the Android ARM64 AOT generator is present and the Release artifact passes signature and alignment verification.
