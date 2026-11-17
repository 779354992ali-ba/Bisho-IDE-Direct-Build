# Bisho IDE Package85

Package85 focuses on the real local-build pipeline's project-input stage.

## Streaming project staging

When a project is selected through Android's Storage Access Framework, Bisho IDE now streams the project tree from the SAF content provider directly into app-private storage using Android `ContentResolver`. It no longer reads every source file into a Dart `Uint8List` before copying it.

The staging operation:

- Requires a SAF tree URI.
- Streams with a fixed 256 KiB buffer.
- Enforces 20,000 files, 1 GiB total source data, and 64 directory levels.
- Rejects unsafe names, duplicate destinations, and path traversal.
- Skips `.git`, `.dart_tool`, `build`, and `.idea`.
- Emits progress and checks cancellation while copying.
- Requires `pubspec.yaml` at the staged project root.

## Build status

The actual Flutter build continues to run through the installed ARM64 PRoot runtime. This source package does not itself contain that multi-gigabyte runtime, and no physical-device APK build was run in this development environment. Package85 is an implementation improvement, not a claim that local build is now fully certified.

See `PACKAGE85_CHANGELOG.md` and `PACKAGE84_TEST_REPORT.md` for implementation and validation boundaries.
