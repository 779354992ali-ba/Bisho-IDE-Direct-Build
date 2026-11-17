# Bisho IDE Package84

Package84 improves the path from **files installed** to **tools actually executable** and from **Flutter exited successfully** to **APK verified**.

## In-app engine probe
Open the Flutter preview/build panel and use **اختبار تشغيل المحرك فعليًا** after installing an engine. The probe starts PRoot and runs Flutter, Java, sdkmanager and ARM64 Android build tools inside the guest root filesystem. It fails closed on timeout or any non-zero exit.

## APK acceptance
Every successful build now needs:
1. Flutter build command exit code 0.
2. A non-empty APK (at least 64 KiB).
3. `apksigner verify --verbose` success.
4. `zipalign -c -v 4` success.
5. A verification record tied to the current engine manifest SHA-256.

Debug and Release are recorded separately. Debug is useful to validate the ARM64 pipeline; it does not certify Release/AOT.

## Preparing an engine archive
See `PACKAGE82_RUNTIME_BUNDLE_SPEC.md` and run `tools/engine_bundle/validate_and_pack.sh` on a fully provisioned Linux ARM64 host. The script does not download the SDK or grant redistribution rights. Only include SDK components you are permitted to redistribute.

## Current limitation
This source package still does not include the multi-gigabyte PRoot + Linux rootfs + Flutter + JDK + Android SDK runtime. A real supported phone and a real runtime archive are required for end-to-end validation.
