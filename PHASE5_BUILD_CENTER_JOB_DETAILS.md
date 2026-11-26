# Phase 5 — Cloud Build Center job status detail

## Implemented
- Workflow progress now reports completed, failed, skipped, active, and queued/waiting job counts separately.
- Skipped steps count as finished work for the active job's approximate progress; this avoids understating progress when workflows intentionally skip steps.
- The Build Center displays the active, waiting, failed, and skipped counts alongside the existing overall percentage and completed-job count.
- Malformed job entries are ignored safely, and progress remains clamped to the 0–100% range.
- Existing workflow dispatch, run lookup, diagnostic ZIP download, APK download, and SHA-256 verification flows were not changed.

## Regression coverage
- Added cases for failed/skipped/active/waiting summaries, malformed job entries, and malformed step payloads.
- Tests have not been executed; this is a source-level implementation only.

## Validation status
- Static source inspection confirms the parser, UI summary, and regression tests are present.
- Flutter analyze and test remain pending.
- No workflow was triggered, no APK build was started, and the local ARM64 engine/runtime was not modified.
