# Package 74 — Automatic GitHub Actions workflow discovery

## Changes
- The GitHub uploader now checks the selected workflow path against the files actually present in the project.
- If the requested workflow is absent and exactly one `.yml` or `.yaml` file exists under `.github/workflows/`, Bisho IDE automatically selects that file. This supports both generated projects using `build-android.yml` and the Bisho IDE repository using `main.yml`.
- The resolved workflow filename is returned by the repository upload service and used for workflow dispatch and subsequent build-status tracking.
- Bumped the Android build number to `1.0.0+74`.

## Validation
- Source-level checks confirm the resolved workflow is used for dispatch and status tracking.
- Flutter/Dart SDK are not installed in this environment; `flutter analyze`, `flutter test`, and APK build remain to be run in GitHub Actions or a Flutter-enabled environment.
