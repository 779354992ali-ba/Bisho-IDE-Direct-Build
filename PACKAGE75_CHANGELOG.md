# Package 75 — Portable archive path validation

## Changes
- ZIP import now rejects file paths that collide on case-insensitive file systems, such as `lib/Main.dart` and `LIB/main.dart`.
- ZIP import/export now validate explicit directory entries as well as files, rejecting parent directories whose spelling differs only by letter case.
- File-versus-directory prefix collisions are checked case-insensitively, including explicit ZIP directory entries.
- ZIP export budgeting now detects case-insensitive duplicate paths before archive assembly.
- Existing path traversal, duplicate, entry-count, and expanded-size protections remain in place.
- Bumped the package version to `1.0.0+75`.

## Validation status
- Added focused regression tests for case-only file collisions, directory spelling collisions, file/directory collisions, and export-budget duplicates.
- Tests and APK build were intentionally not run in this development phase; Flutter/Dart SDK availability is not assumed.
