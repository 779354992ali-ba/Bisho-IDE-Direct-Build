# Bisho IDE Package88 — Runtime bundle certification and safe extraction

## Engine installation and archive safety

- ZIP extraction now rejects non-canonical path components, Windows drive-prefixed paths, duplicate names, and distinct ZIP names that resolve to the same canonical filesystem target.
- The executable inventory is restricted to files under `runtime/` and `rootfs/`; metadata outside the Linux runtime cannot be made executable by the bundle.
- Engine installation now requires an explicit `debugBuildSupported: true` certification in the manifest. The certification is produced by `tools/engine_bundle/validate_and_pack.sh` only after a real Flutter Android ARM64 Debug APK smoke build succeeds and its signature and ZIP alignment are checked.
- `releaseAotSupported` must be a JSON boolean when present.

## Release build policy

- Release builds are blocked unless the exact engine bundle declares `releaseAotSupported: true`.
- The bundle publisher sets this flag only after a full Release/AOT smoke build, APK signature verification, and ZIP alignment check pass. Merely finding `gen_snapshot` is not treated as proof.
- Debug and Release certification remain separate; a Debug-capable bundle is not advertised as Release-ready.

## Bundle publisher hardening

- The ARM64 packer checks that PRoot, Java, and Flutter's Dart VM are Linux ARM64 executables before running the smoke build.
- It verifies that the output ZIP is outside the source runtime directory and that required packaging utilities are installed.
- The example manifest is intentionally uncertified (`debugBuildSupported: false`) and cannot be installed unchanged.

## Validation limits

- Shell syntax, JSON/YAML/XML parsing, ZIP integrity, and Kotlin parser-level syntax checks were performed.
- Flutter analyze/tests, Android Gradle compilation, device-side PRoot execution, and APK builds were not available in this environment. Package88 therefore does not claim that a real engine bundle or APK has been produced.
