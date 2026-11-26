# Local engine installer — storage exhaustion safeguards

## Scope
This change is limited to admission checks and failure diagnostics in the existing Android-side archive installer. It does not replace, rebuild, download, patch, or modify the ARM64 engine payload, Alpine 3.24.4 contents, PRoot 5.1.0 binaries, package database, or runtime scripts.

## Changes
- Increased the extraction free-space safety reserve from 512 MiB to 1 GiB.
- Added a best-effort filesystem inode headroom check (5,000 available inodes) at install admission, every 64 TAR entries, and immediately before creating each RootFS symbolic link.
- Explicitly recognizes `ENOSPC` / `No space left on device` from symbolic-link creation even when filesystem counters appear healthy, and reports the actual remaining byte/inode values plus the RootFS link path instead of exposing only a generic `Bad state` message.
- Added an in-app installation guide that explains archive selection, checksum verification, temporary extraction, activation/rollback, and the required storage reserve.
- Preserve the existing staging/rollback behavior: a failed extraction is not activated and the previously installed engine is not replaced.

## Validation
- Source-level review of the Kotlin guard and its call sites only.
- No Android build, device install, RootFS extraction, PRoot execution, or engine rebuild was run as part of this change.
- Device validation is still required to confirm the reported free-space/inode behavior on the target phone.
