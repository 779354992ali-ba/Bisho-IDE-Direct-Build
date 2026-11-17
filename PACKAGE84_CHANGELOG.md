# Package84 — Real Runtime Probe & APK Verification

## Implemented
- Added a native `probeEngine` operation that actually launches PRoot and executes Flutter, Java, sdkmanager, AAPT2, AIDL and apksigner inside the installed Linux rootfs.
- Added a 120-second probe timeout and a bounded diagnostic log returned to the app.
- Added a visible **اختبار تشغيل المحرك فعليًا** action in the local build panel.
- Split local build proof into Debug and Release records. Debug success no longer implies Release/AOT readiness.
- Added post-build APK signature verification with `apksigner` and 4-byte ZIP alignment verification with `zipalign` for both modes.
- Debug and Release verification records are bound to the installed engine manifest SHA-256 and are invalidated when a new engine is installed.
- Added `tools/engine_bundle/validate_and_pack.sh` to validate and package an already provisioned Linux ARM64 engine with dereferenced symlinks, an executable inventory, a manifest, and a final SHA-256.

## Not claimed
- No complete runtime rootfs or multi-gigabyte engine archive is included in this source ZIP.
- No Flutter/Gradle/Android APK build was executed in this development container.
- Release/AOT remains conditional on the exact `android-arm64-release/linux-arm64/gen_snapshot` artifact being present and executable.
- The bundle packer is a reproducible validation/packaging tool; it does not manufacture proprietary SDK files or bypass their licenses.
