# Bisho IDE Package 99 — Diagnostics Download

## Added
- Download GitHub Actions diagnostic artifacts for a selected workflow run, including failed runs.
- Validate the ZIP signature/structure and require `BUILD_DIAGNOSTICS.txt` before saving.
- Save the original diagnostic ZIP in the selected project folder without extracting untrusted paths.
- Keep APK download gated on a successful workflow conclusion.

## Verification limits
This package has not been run through Flutter analyze, Flutter tests, or an Android APK build in this environment. Run the `Build Flutter APK` workflow on GitHub to validate it on the hosted toolchain.
