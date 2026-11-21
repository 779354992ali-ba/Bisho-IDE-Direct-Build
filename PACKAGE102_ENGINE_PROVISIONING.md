# Package102 — Native ARM64 engine provisioning pipeline

## What this adds

- Adds `.github/workflows/provision-local-engine-arm64.yml`, a manually dispatched provisioning pipeline on a native `ubuntu-24.04-arm` runner.
- Builds a separate Ubuntu 24.04 ARM64 guest rootfs and provisions pinned Flutter 3.27.4, Dart, OpenJDK 17, Android API 35, Build Tools 35.0.1, and ARM64 replacements for `aapt2`, `aidl`, `zipalign`, and `split-select`.
- Resolves the Android command-line-tools SHA-1 from Google's repository metadata before accepting the downloaded archive.
- Verifies the published SHA-256 of the ARM64 Build Tools archive and each replacement executable.
- Retrieves the previously successful Android-linked PRoot artifact from this branch, then calls the existing engine packer. The packer must complete a real ARM64 Debug APK build and verify APK signature and ZIP alignment before the engine ZIP is uploaded.
- Adds CI checks for the workflow YAML, explicit license gate, pinned source/artifact hashes, and packer invocation.

## License safety

The workflow defaults `accept_android_sdk_licenses` to `false` and stops before provisioning unless the person manually dispatching the workflow changes it to `true`. Do not select `true` until you have personally reviewed and explicitly accepted the applicable Android SDK license terms. The workflow then invokes Google's `sdkmanager --licenses`; it does not synthesize license files.

## How to run after reviewing and accepting the terms

1. Open the repository's Actions tab.
2. Select **Provision Bisho Flutter ARM64 Local Engine**.
3. Select **Run workflow** on branch `package100-local-engine-provisioning`.
4. Only if you have reviewed and accepted the Android SDK terms, enable `accept_android_sdk_licenses`.
5. Wait for **Assemble and smoke-test the complete local engine** and **Upload verified local engine bundle** to succeed.
6. Download artifact `Bisho-Flutter-Local-Engine-ARM64`.

## Verification boundary

Creating this workflow does not mean the engine is already provisioned. It has not been run yet. A successful workflow run proves the bundle passed the Linux ARM64 packaging smoke test; installation and the PRoot ptrace/rootfs probe on a physical Android ARM64 phone are still required before claiming device readiness. Release/AOT remains gated by the packer.
