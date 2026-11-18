# Bisho IDE Package93

Package93 continues the local-build foundation work from Package92.

- Native Release/AOT diagnostics now expose a dedicated proof flag.
- `tools/engine_bundle/bootstrap/alpine-aarch64.json` pins the Alpine 3.24.4 aarch64 archive and official integrity sidecars.
- `PACKAGE93_CHANGELOG.md` documents implemented work, security requirements, and outstanding integration.

Important: Package93 is a development source package, not a verified local-build release. Alpine TAR.GZ extraction, PRoot integration, Flutter/JDK/Android SDK provisioning, offline dependency caching, and physical-device validation remain outstanding.
