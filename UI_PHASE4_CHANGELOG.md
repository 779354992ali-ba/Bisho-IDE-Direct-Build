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
