# Bisho IDE — Package 100 development continuation

## Phase 1 — Editor command palette
- Fixed command matching so word-prefix searches split text on actual whitespace instead of a literal backslash sequence.
- Added regression coverage for word-prefix ranking, fuzzy initials, stable ordering, case/whitespace normalization, and result limits.
- The tests are committed but have not been executed; no pass is claimed.

## Phase 2 — Project creation and portability
- Hardened project-name and relative-path validation against Windows-reserved device names, control characters, forbidden filename characters, trailing dots/spaces, drive-qualified paths, and traversal.
- Added regression cases for reserved names and non-portable paths.
- Existing generated project templates and write flows were left intact; this change only rejects unsafe or non-portable input before project creation.
- Regression tests are committed but not executed yet.

## Phase 3 — Backup restore safety
- Backup decoding now checks the combined entry count, declared per-file size, aggregate declared size, and exact base64 encoded length before allocating decoded file buffers.
- Directory entry types are validated before processing file payloads; existing checksum and path-conflict validation remains in place.
- Added regression tests for oversized declarations, aggregate limits, excessive entry counts, and encoded-length mismatches.
- Tests have not been executed; static checks only. No build was started.

## Phase 5 — Cloud Build Center
- Added GitHub Actions job-level progress calculation and display.
- Added progress model tests.
- Kept APK download gated on successful workflow completion and existing checksum verification.

## Phase 6 — Local ARM64 engine integration
- Hardened parsing of native engine diagnostic responses.
- Made read-only engine probing return structured failures instead of leaking channel exceptions.
- Changed health readiness to require zero warnings as well as zero failures.
- Added regression tests for malformed diagnostics and engine readiness.
- Did not modify the existing ARM64 engine, Alpine RootFS 3.24.4, PRoot 5.1.0, package database, installer, or execution flow.

## Phase 7 — Editor experience
- Fixed split-editor word-wrap state scope.
- Added a split-editor-specific word-wrap toggle.

## Phase 8 — Security review
- Re-inspected SAF child-name validation and overwrite handling.
- Re-inspected GitHub PAT storage: token remains in Flutter Secure Storage and is excluded from cloud build preferences.
- No credential values were added to logs or the new progress model.

## Phase 9 — Validation
- Added tests for the new progress model, malformed engine diagnostic payloads, and engine-health readiness.
- Fixed the analyzer error `undefined_identifier: _wordWrap` identified in the preceding GitHub Actions run.
- The existing run failed at `flutter analyze`; tests and APK compilation were skipped.
- No tests have been executed for this continuation, so no test success is claimed.

## Workflow constraints
- Development commits are on `work/ten-phase-continuation` to avoid triggering the branch-specific build workflow during editing.
- No build or APK generation was initiated by this continuation.
- Merge back to the integration branch and full validation remain pending.
