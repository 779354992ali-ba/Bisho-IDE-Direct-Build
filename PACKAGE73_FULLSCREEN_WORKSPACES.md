# Package 73 — Full-screen Terminal and Editor

## Changes
- Opening the terminal now pushes a dedicated full-screen route instead of only revealing the short bottom panel.
- The full-screen terminal keeps the active project context and existing SAF-backed terminal commands.
- Opening a file from the terminal returns to the editor and opens the selected file.
- The editor's dedicated full-screen route remains the full-screen editing experience, sharing the same CodeController so edits are preserved.
- Repeated terminal-open actions are guarded while the full-screen terminal route is active.

## Validation
- Source-level review completed.
- `git diff --check` equivalent whitespace check completed.
- Flutter analyze, tests, and APK build still need to be run in the project's Flutter/GitHub Actions environment.
