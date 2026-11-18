# Bisho IDE Package94

Package94 adds the first separate Alpine TAR.GZ installation path and an
upstream-source Android ARM64 PRoot build workflow. Start with
`PACKAGE94_CHANGELOG.md` and `tools/proot/README_ANDROID_ARM64.md`.

Alpine installation is available through `AlpineRootfsInstaller.install()`.
It downloads and checks the official SHA-256 sidecar before native extraction.
The Alpine rootfs is only a bootstrap filesystem; it does not provide the
Flutter/JDK/Android SDK build toolchain. Do not label local or offline builds
ready until a complete toolchain and offline smoke-build proof are installed.
