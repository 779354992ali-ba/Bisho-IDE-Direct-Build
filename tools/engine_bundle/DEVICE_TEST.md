# Bisho ARM64 engine: on-device acceptance test

The CI packer runs a native ARM64 \`chroot\` smoke build. That does **not** certify the Android PRoot binary. A bundle is not ready for in-app use until the device test below passes.

## Run from Termux

1. Extract the engine ZIP into \`$HOME/bisho-engine\` so the directory contains \`runtime/proot\` and \`rootfs/\`.
2. To collect the read-only PRoot/seccomp-order comparison log, run:

   ```bash
   bash tools/engine_bundle/diagnose_proot_seccomp.sh "$HOME/bisho-engine"
   ```

3. From the repository root, run:

   \`\`\`bash
   bash tools/engine_bundle/test_on_device.sh "$HOME/bisho-engine"
   \`\`\`

The script tests, in order:

- Android PRoot version and a shell command inside the ARM64 rootfs.
- Android DNS discovery and guest resolver setup.
- Flutter, Java 17, and \`sdkmanager\` versions.
- Flutter Android precache and a fresh ARM64 Debug APK build.
- \`apksigner verify\`, \`zipalign -c -v 4\`, and \`aapt2 dump badging\`.
- Android Package Installer installation, followed by launching the smoke app and checking that its process is running.

The Package Installer step requires a human confirmation. If Android asks, allow Termux to install unknown apps and tap **Install**. The script does not bypass Android's confirmation.

A full log is saved under \`$HOME/bisho-engine-device-test-*.log\`. If \`termux-clipboard-set\` is installed, the latest log is copied to the clipboard automatically.

A successful Termux test is evidence for that exact engine bundle on that device. The app's own engine probe performs its own on-device test and keeps local builds disabled until its verification record is present.
