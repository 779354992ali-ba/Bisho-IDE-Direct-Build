# Bisho IDE Package88

Package88 strengthens the path from a supplied ARM64 toolchain archive to a genuinely certified local Flutter build engine.

### Important behavior

A runtime ZIP is no longer accepted merely because it contains Flutter, Java, and Android SDK paths. Its manifest must state `debugBuildSupported: true`, and the supported publisher script writes that value only after a real Android ARM64 Flutter Debug smoke build succeeds, followed by APK signature and ZIP-alignment verification.

Release is independently gated by `releaseAotSupported: true`. The packer sets it only after a full Release/AOT smoke build succeeds. A bundle that supports Debug only remains usable for Debug and is explicitly prevented from claiming Release readiness.

### Prepare a runtime bundle

See `PACKAGE82_RUNTIME_BUNDLE_SPEC.md`, `engine-manifest.example.json`, `engine-executables.example.txt`, and `tools/engine_bundle/validate_and_pack.sh`.

Run the packer on a Linux ARM64 host with an already provisioned ARM64 PRoot rootfs, Flutter SDK, JDK 17, and compatible Android SDK Build Tools. It may take up to 60 minutes for each smoke build. The script does not download proprietary or licensed components on the user's behalf.

### Validation status

Static package checks passed. No Flutter/Gradle build or Android device execution was possible in the current development environment. A real runtime ZIP is still required before Bisho IDE can perform a local build on a phone.
