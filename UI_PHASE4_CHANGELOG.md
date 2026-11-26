# Bisho IDE — Phase 4 UI Refresh

This phase is a presentation-layer refresh on top of Phase 3. Existing editor actions, project services, build services, local-engine integration, terminal integration, and file operations are intentionally retained.

## UI changes
- Added a new welcome/hero panel to the workspace dashboard with live project, active-file, and language context.
- Added direct primary actions for opening/starting a project and creating a file.
- Added a visible saved/unsaved workspace hint.
- Refined dashboard background with a layered gradient, panel surfaces, spacing, borders, and touch targets.
- Refined dashboard action cards for clearer mobile readability.
- Added a one-tap code search action and theme toggle to the app bar.
- Refined editor tab strip and file explorer header styling.

## Compatibility / preservation
- No engine binaries, RootFS, Alpine installation logic, build workflows, project services, or package identifiers were intentionally changed.
- No existing dashboard action callbacks were removed or replaced.
- Existing theme persistence remains in use.

## Validation
- Source-level patch applied.
- Flutter/Dart SDK is not installed in this editing environment, so `dart format`, `flutter analyze`, tests, and APK build could not be run here. Run them in the project's configured Flutter environment before publishing.


# Phase 5 — Build workflow persistence and reliability

## Changes
- Persist the GitHub repository, workflow filename, branch, and Flutter SDK version used by the cloud build screen.
- Restore those non-secret settings when the build screen is opened again.
- Serialize preference writes so rapid field edits cannot leave an older value as the final saved configuration.
- Keep the GitHub Personal Access Token out of this settings model and its serialized data.
- Keep local Debug/Release mode persistence independent from cloud build settings.
- Preserve the existing ARM64 engine, Alpine RootFS, and local build execution path.

## Validation
- Added unit tests for defaults, persistence round-trip, malformed stored data recovery, and credential exclusion.
- CI must complete Dart analysis, Flutter tests, Android APK compilation, and JVM tests before this phase is considered build-verified.
