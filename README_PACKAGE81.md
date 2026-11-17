# Package81

Package81 improves the final artifact path for local builds: APK files are copied to the user's project folder through Android SAF using native streaming I/O rather than being loaded into Dart memory. It also tightens manifest-driven runtime paths, verification marker handling, and installer preflight checks.

This is a source package, not proof that local building is operational. A compatible runtime archive and a successful device-side release APK build are still required. See `PACKAGE81_CHANGELOG.md`.
