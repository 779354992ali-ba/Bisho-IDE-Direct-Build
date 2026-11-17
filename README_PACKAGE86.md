# Bisho IDE Package86

Package86 focuses on the real local-build pipeline:

- Retains a verified APK outside the temporary project staging folder.
- Binds readiness proof to the exact APK SHA-256 and engine manifest digest.
- Separates the large engine installation storage requirement from the smaller post-install build reserve.
- Uses bounded Gradle memory/workers for mobile devices.
- Selects the newest complete Android Build Tools set consistently.
- Runs environment inspection away from the Android UI thread.

See `PACKAGE86_CHANGELOG.md` and `PACKAGE86_TEST_REPORT.md`.

**Important:** this source package does not contain the large ARM64 runtime. A real Debug/Release build still requires a compatible PRoot/Linux/Flutter/JDK/Android SDK bundle and physical-device validation.
