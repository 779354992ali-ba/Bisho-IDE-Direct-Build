# Phase 5 — Persistence regression coverage

## Changes in this continuation
- Added focused tests for safe defaults, settings round-trip, malformed JSON recovery, wrong-type preference recovery, and exclusion of credentials from remote build settings.
- Added build-history tests for newest-first ordering, metadata retention, bounded retention (50 records), and malformed-file recovery.
- Added file-version-history tests for newest-first snapshots, duplicate suppression, bounded retention (30 snapshots), and per-file isolation.
- Hardened `RemoteBuildSettings.load()` so malformed or type-incompatible optional preferences fall back to defaults instead of escaping as an exception.
- Fixed the typed SharedPreferences read boundary: `getString()` itself is now inside the recovery guard, so a stored value with an incompatible runtime type cannot prevent the cloud build screen from loading.
- Added a regression test for individually malformed decoded fields; valid fields are retained while invalid fields fall back independently.

## Files
- `lib/core/services/remote_build_settings.dart`
- `test/remote_build_settings_test.dart`
- `test/core/services/build_history_store_test.dart`
- `test/core/services/file_version_history_test.dart`

## Validation status
- Changes are committed to `fix/app-stream-rootfs-install`.
- Tests were added and statically reviewed, but Flutter tests have not yet been executed in this development-only pass.
- No APK build was started.
- The existing ARM64 engine, Alpine RootFS, local build runner, and GitHub Actions build path were not modified.

## Additional project safety coverage in the same continuation
- ZIP archive path normalization, traversal rejection, absolute/drive path rejection, duplicate and case-collision detection, file/directory collisions, and export-budget enforcement.
- Full-project backup round-trip, checksum/size tamper detection, path traversal rejection, portable-name restrictions, and unsupported-version rejection.
- Backup catalog ordering, manifest integrity verification, unsafe/duplicate identifier rejection, and file-level change comparison.

Additional test files:
- `test/core/services/project_archive_validator_test.dart`
- `test/core/services/project_backup_service_test.dart`
- `test/core/services/project_backup_repository_test.dart`

These tests remain unexecuted until the agreed validation stage. A successful test run and a separate APK build are still required before final release approval.
