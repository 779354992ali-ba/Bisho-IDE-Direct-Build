# Phase 5 — Persistence regression coverage

## Changes in this continuation
- Added focused tests for safe defaults, settings round-trip, malformed JSON recovery, wrong-type preference recovery, and exclusion of credentials from remote build settings.
- Added build-history tests for newest-first ordering, metadata retention, bounded retention (50 records), and malformed-file recovery.
- Added file-version-history tests for newest-first snapshots, duplicate suppression, bounded retention (30 snapshots), and per-file isolation.
- Hardened `RemoteBuildSettings.load()` so malformed or type-incompatible optional preferences fall back to defaults instead of escaping as an exception.

## Files
- `lib/core/services/remote_build_settings.dart`
- `test/remote_build_settings_test.dart`
- `test/core/services/build_history_store_test.dart`
- `test/core/services/file_version_history_test.dart`

## Validation status
- Changes were committed to `fix/app-stream-rootfs-install`.
- Flutter tests and APK build were intentionally not run in this development-only pass, per the project workflow.
- The existing ARM64 engine, Alpine RootFS, local build runner, and GitHub Actions build path were not modified.
