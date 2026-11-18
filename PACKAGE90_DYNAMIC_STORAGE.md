# Package90 — Dynamic Local Engine Storage

## Changes
- Removed the unconditional 20 GB installation preflight.
- Installation checks the actual HTTPS archive Content-Length against free app storage and requires a 1 GB reserve before download.
- After download, native installation requires a 1 GB remaining reserve.
- ZIP extraction continuously checks free space and stops before falling below 512 MB.
- The archive remains capped at 8 GB and expanded content remains capped at 12 GB.
- The normal local build reserve remains 5 GB because Gradle and Flutter build workspaces can grow substantially.

## Important
This removes an arbitrary fixed 20 GB gate; it does not make a full Flutter toolchain small. A device with 4.5 GB free may download/install only a sufficiently small bundle and still fail the build preflight, which continues to require 5 GB. No official, verified ARM64 runtime archive URL or SHA-256 is bundled in this package. The installer still requires a trusted archive URL and checksum. Debug must pass the device-side smoke build before local building is enabled; Release/AOT remains separately gated.

## Validation status
- Source edits and whitespace review only.
- Flutter/Dart analysis, Kotlin compilation, GitHub Actions APK build, and real-device tests have not been run for Package90.
