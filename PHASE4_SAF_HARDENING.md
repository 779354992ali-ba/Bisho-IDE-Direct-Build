# Phase 4 — Android SAF safety hardening

## Implemented
- SAF child names reject ASCII control characters and DEL in addition to path separators, traversal segments, reserved device names, and non-portable filename characters.
- Added a 255-byte UTF-8 child-name limit while preserving valid Arabic and supplementary Unicode characters.
- Recursive SAF tree cleanup now has both depth and entry-count limits (defaults: 64 levels and 10,000 entries) and stops with an explicit error when a limit is exceeded.
- Existing persisted-permission picker behavior, MIME mapping, exact-name repair, overwrite handling, and SAF APIs remain unchanged.

## Regression coverage
- Added tests for control characters, the 255-byte boundary, overlong ASCII and multibyte Unicode names, and valid Arabic/emoji names.
- SAF recursive deletion limits require device/provider integration testing; no platform behavior is claimed as tested.

## Validation status
- Static source checks confirm the new guards and test cases are present.
- Flutter tests/analyzer have not been run.
- No APK build was started; local ARM64 engine/runtime files were not changed.
