# Bisho IDE Package 83

Package 83 hardens local build engine validation and verification. It rejects runtime bundles whose Flutter/JDK/Android SDK paths escape the declared Linux root filesystem, caps manifest parsing, rejects duplicate ZIP entries, and binds Release verification to the installed manifest hash. It also removes any previous APK output before a new build.

See `PACKAGE83_CHANGELOG.md` for changes and validation limits, and `PACKAGE82_RUNTIME_BUNDLE_SPEC.md` for the required runtime archive format.

**Important:** Package 83 does not include a real runtime bundle. Local APK build is not yet certified until a compatible ARM64 runtime is installed and Debug/Release builds pass on the target phone.
