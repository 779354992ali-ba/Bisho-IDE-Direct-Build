# Phase 8 — Security hardening

## Implemented
- Validate GitHub Personal Access Token input before verification or secure-storage writes. Tokens remain stored only through Flutter Secure Storage; no token values are written to preferences, project files, logs, or UI errors.
- Validate GitHub owner/repository identifiers, workflow paths, branch names, and positive workflow-run IDs before constructing API requests.
- Validate each SAF-provided file and directory name before adding it to a Git tree path. Invalid provider entries are skipped rather than uploaded under unsafe paths.
- Sanitize GitHub API error messages. UI-facing errors use stable Arabic messages and HTTP status codes instead of echoing arbitrary server response text.
- Reuse the trimmed, validated token throughout project upload and workflow operations.

## Regression coverage added
- Empty and whitespace-containing tokens are rejected before network access.
- Traversal-like owner/repository/workflow inputs and invalid branch names are rejected before network access.
- Arbitrary server error text is not echoed into exceptions.
- Non-positive workflow run IDs are rejected before network access.

## Scope and compatibility
- Changes are limited to GitHub integration input validation, error handling, and SAF-to-Git path handling.
- Existing API routes, upload format, secure-storage key, workflow dispatch behavior, and APK/diagnostics verification flow are retained.
- No changes were made to the existing ARM64 engine, Alpine Linux 3.24.4 RootFS, PRoot 5.1.0, package database, installers, native runtime, or execution flow.

## Validation status
- Source-level review and regression test additions are committed.
- Flutter analyzer and tests have not been run in this continuation; test success is not claimed.
- No GitHub Actions workflow, build, or APK generation was triggered.
