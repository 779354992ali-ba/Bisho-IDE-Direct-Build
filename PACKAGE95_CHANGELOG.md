# Package95 changes

- Alpine installer is now reachable from the local-build UI.
- Progress and cancellation are exposed in the UI.
- Alpine installation state is read from the native filesystem and displayed separately from engine/toolchain readiness.
- Added an ARM64 toolchain contract and explicit offline acceptance gates.
- No PRoot build, SDK download, offline cache creation, APK build, or device test is claimed.
