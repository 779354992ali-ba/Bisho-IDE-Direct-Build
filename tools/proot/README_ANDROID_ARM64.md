# PRoot Android ARM64 build lane

Bisho does not download a third-party prebuilt PRoot binary. The workflow
`.github/workflows/build-proot-android-arm64.yml` checks out upstream
`proot-me/proot` tag `v5.5.0`, cross-compiles for Android API 24 / AArch64
using Android NDK `29.0.14206865`, and records the resolved source commit and
SHA-256 in the workflow artifact.

This is a reproducible build recipe, **not proof that the binary works on a
particular Android kernel**. The first successful workflow must be inspected;
the produced ELF must be tested on the target phone for `--version`, ptrace,
PRoot rootfs entry, bind mounts, and execution of `/bin/sh`. Do not package the
binary into a production engine before those tests pass. Keep the upstream
license and corresponding source available with any distributed binary.

Upstream reference: https://github.com/proot-me/proot/releases/tag/v5.5.0
