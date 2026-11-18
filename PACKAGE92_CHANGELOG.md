# Package92 changelog

## Local build verification correctness
- Fixed Release/AOT status parsing in Dart: it now consumes the dedicated native `releaseBuildVerified` field.
- Added the dedicated native field, derived from the independently persisted Release APK verification record.
- Added an explicit false Release state to native error/fallback diagnostics.
- Added a regression test ensuring Debug verification cannot be mistaken for Release/AOT verification.

## Bootstrap engineering notes
- Recorded the official Alpine 3.24.4 aarch64 Mini RootFS endpoint and the required checksum-sidecar validation flow.
- Documented that the current installer accepts ZIP only and cannot safely extract Alpine `.tar.gz` archives.
- Documented PRoot provenance/licensing requirements and the ARM64 Android SDK/toolchain compatibility gate.

## Validation status
- Source-level checks: performed (balanced Kotlin/Dart delimiters; expected fields and test assertions present).
- ZIP integrity: checked after packaging.
- Flutter/Dart tests, Android Gradle compilation, APK build, PRoot execution, and physical-device tests: not run in this environment.
