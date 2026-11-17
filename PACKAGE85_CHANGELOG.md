# Package85 — Streaming Project Staging for Real Local Builds

## Implemented

- Moved project staging from Dart's `readFileBytes()` loop to Android's `ContentResolver` streaming APIs.
- SAF files are copied in 256 KiB chunks directly into the app-private build workspace; source files are no longer materialized as full `Uint8List` objects in Dart memory.
- Added explicit SAF tree-URI validation, canonical destination containment checks, duplicate-name rejection, and rejection of path separators / control characters.
- Preserved the existing limits: maximum 20,000 files, 1 GiB total source data, and 64 directory levels.
- Continue excluding `.git`, `.dart_tool`, `build`, and `.idea` from the staged build context.
- Added progress events during staging and cancellation checks between files and while streaming each file.
- Verify that the staged directory contains `pubspec.yaml` before handing it to the native Flutter build runner.
- Kept all build execution inside the app-private Linux/PRoot engine; Dart does not invoke shell commands.

## Why this matters

Large projects previously required a full file-sized byte array in Dart before writing each file, causing avoidable memory pressure and possible OOM failures on Android. Package85 streams project files natively with a fixed-size buffer, making project staging substantially more memory predictable.

## Not claimed

- This package does not include a complete PRoot/Linux/Flutter/JDK/Android SDK runtime bundle.
- Flutter/Dart SDK and Android SDK are not available in the development container, so `flutter analyze`, `flutter test`, Gradle compilation, Android APK build, and on-device SAF validation were not run.
- Actual Debug and Release APK production still requires installing a compatible, independently validated ARM64 runtime bundle and testing on a physical Android device.
