# Package101 — Flutter ARM64 source pinning and license-safe provisioning

## Changes
- Resolved Flutter tag `3.27.4` to immutable Git commit `d8a9f9a52e5af486f80d932e838ee93861ffd863`.
- Recorded the exact community setup reference commit `6a6eb5e13ce99d99e5604b6be83ecb46b3098e02`; it is reference material, not an installer to execute in production.
- Recorded the command-line tools archive build ID observed in that pinned setup script (`14742923`) while explicitly leaving its SHA-256 unverified.
- Made the Android SDK license rule explicit: never create or silently accept license files. Provisioning may package them only after the publisher/user has reviewed and explicitly accepted the applicable terms.
- Kept the toolchain status as not provisioned. No runtime ZIP, device-side validation, or local Flutter build is claimed.

## Verified evidence
- Package100 PRoot workflow run `44875675534` succeeded at branch head `ff2f34a37b021e7df879ca74d6e9a8a6c3d76aae`.
- Artifact `bisho-proot-android-arm64-v5.5.0` was uploaded (artifact ID `14695767870`, size 300,901 bytes, SHA-256 digest `87516188a62027e90ead5c80ab178da9c2499ea07f5750ed8eb27d88265acb1c`).
- The Flutter app workflow also succeeded at the same head.

## Remaining
- Resolve and verify exact Flutter bootstrap/Dart/engine artifact hashes.
- Verify Android command-line tools archive checksum and ARM64 sdkmanager execution.
- Provision a complete Linux ARM64 rootfs with OpenJDK 17 and API 35 SDK.
- Obtain explicit SDK license acceptance before packaging license files.
- Run the real Debug smoke build through native Linux ARM64 host PRoot, then install and probe the Android PRoot/runtime on a physical ARM64 device.
- Keep Release/AOT disabled until its own real build proof passes.
