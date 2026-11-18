# Bisho IDE Package 98 — GitHub build diagnostics

## What's new
- Captures `flutter analyze`, `flutter test`, and APK build output into separate log files.
- Always creates a build diagnostics report, including workflow run ID, commit, ref, runner architecture, job status, and toolchain versions when available.
- Uploads a separate `Bisho-IDE-Build-Diagnostics` artifact even when validation or APK building fails.
- Keeps the successful APK artifact name `Bisho-IDE-Release-APK` unchanged so the existing in-app APK download flow remains compatible.

## How to use
1. Push this package's project contents to the `main` branch.
2. Open GitHub Actions and run **Build Flutter APK** with Flutter `3.47.9`.
3. On success, download `Bisho-IDE-Release-APK`.
4. On failure, download `Bisho-IDE-Build-Diagnostics` and inspect `BUILD_DIAGNOSTICS.txt`, `analyze.log`, `tests.log`, or `apk-build.log`.

## Verification boundary
The workflow YAML and package archive can be statically validated here. A real Flutter analyze/test/APK build still requires execution by GitHub Actions; this package does not claim that a new APK has already been built.
