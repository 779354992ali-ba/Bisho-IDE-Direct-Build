# Phase 6 — Read-only local engine diagnostics

## Scope protection
The local ARM64 engine is already built and remains the engine used by Bisho IDE. This phase is diagnostics-only. It does not replace, reinstall, download, rebuild, patch, or alter the engine, Alpine RootFS, PRoot, package database, or execution scripts.

## Implemented
- Local build readiness now requires native confirmation of the installed engine, Alpine RootFS, supported device, verified runtime, and a verified Debug build. A stale or overly optimistic native readiness flag can no longer bypass those gates.
- Added explicit storage knowledge/sufficiency helpers. Unknown storage stays a warning; known insufficient storage is a blocking health failure.
- Added a dedicated Alpine RootFS health check so a present engine binary cannot hide a missing runtime filesystem.
- Kept Release/AOT proof separate from Debug proof; Debug verification does not imply Release verification.

## Regression coverage
- Tests cover missing runtime, missing Alpine, unknown/insufficient storage, and the health report's blocking checks.
- Tests have not been run; no passing result is claimed.

## Validation status
- Static source review only.
- No local engine build, installation, replacement, rootfs extraction, PRoot operation, workflow dispatch, or APK build was performed.
