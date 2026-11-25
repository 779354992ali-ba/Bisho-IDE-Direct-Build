# Phase 6 — Local ARM64 engine diagnostics hardening

## Implemented
- Made native diagnostic parsing tolerant of malformed optional numeric fields and missing-requirements values.
- Numeric diagnostic values accept native numbers or parseable numeric strings; invalid values fall back safely.
- Malformed missing-requirements payloads become an empty list rather than throwing.
- Wrapped the read-only `probeEngine` channel call so PlatformException, missing plugin, and unexpected failures return a structured unsuccessful diagnostic result.
- Corrected engine-health readiness semantics: warnings now prevent the report from claiming that all health checks are ready.
- Added regression tests for malformed native payloads and warning-free engine readiness.

## Preservation constraints
- No engine binary, Alpine RootFS, Alpine release, PRoot binary/version, package database, installer, or runtime execution code was changed.
- No native Android engine implementation was modified.

## Validation
- Tests were added but not executed in this continuation.
- No APK build was started.
- Physical-device verification of Alpine 3.24.4 and PRoot 5.1.0 remains required.
