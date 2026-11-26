# Phase 3 — Backup decoder resource safety

## Implemented
- Rejects manifests whose combined file and directory entry count exceeds the configured maximum before processing file payloads.
- Validates directory entry types before decoding file contents.
- Validates each declared file size and aggregate declared size before base64 decoding.
- Requires the base64 string length to match the declared byte length before decoding, preventing forged small size declarations from triggering oversized decoded buffers.
- Retains per-file checksum verification, normalized path checks, duplicate detection, and file/directory collision checks.

## Regression coverage added
- Oversized declared file size.
- Aggregate declared size beyond the configured maximum.
- Excessive entry count.
- Base64 payload length inconsistent with declared bytes.

## Validation status
- Static inspection confirms the guards and regression tests are present.
- Flutter tests and analyzer have not been run. No test pass is claimed.
- No APK build was started, and the local ARM64 engine/runtime was not modified.
