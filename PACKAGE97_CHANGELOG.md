# Bisho IDE Package 97 — GitHub build pipeline hardening

- Standardized the GitHub Actions and in-app default Flutter version to 3.47.9, matching the previously successful Bisho build environment.
- Updated the GitHub repository service test expectation for the selected Flutter version.
- Hardened the release workflow with Java/Gradle caching, Flutter diagnostics, Android project/XML preflight, analyzer and test gates, release APK verification, SHA-256 checksum, and build metadata.
- Preserved the Package96 in-app artifact download contract: `Bisho-IDE-Release-APK`, `app-release.apk`, and `SHA256SUMS.txt`.
- Set the Android Gradle wrapper executable bit in the package archive.

## Validation

- Static source and workflow checks are performed during packaging.
- A real GitHub Actions run was not started because the linked GitHub integration cannot currently see `779354992ali-ba/Bisho-IDE-Direct-Build` (repository lookup returned no accessible repository).
- Flutter analyze/tests and APK build must be confirmed by GitHub Actions; they were not run in this environment.
