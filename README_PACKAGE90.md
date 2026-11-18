# Bisho IDE Package90

Package90 adjusts local-engine installation storage handling to use the actual archive size rather than a blanket 20 GB gate.

See `PACKAGE90_DYNAMIC_STORAGE.md` for behavior and limitations.

The local engine is not yet bundled: a trusted ARM64 PRoot/Linux + Flutter + JDK + Android SDK archive and its SHA-256 are still required. The local build button remains fail-closed until an actual on-device Debug APK build passes verification.
