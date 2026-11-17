# Bisho IDE Package87 — Android Gradle Wrapper preparation

## Main change

Fixed a real local-build failure that can occur after importing a Flutter project through Android's Storage Access Framework (SAF): copying file bytes does not preserve POSIX executable permissions. Flutter's Android build invokes `android/gradlew`, so the staged wrapper could fail with `Permission denied` even when the source project was valid.

Before starting PRoot, Package87 now:

- Requires the staged project to contain a real `android/gradlew` script.
- Checks that `android/gradle/wrapper/gradle-wrapper.jar` exists and is non-empty beyond a conservative minimum.
- Checks `gradle-wrapper.properties` and requires a usable `distributionUrl`.
- Allows HTTPS Gradle distributions or a local `file:/` distribution; rejects plain HTTP.
- Corrects escaped `\:` in Java-properties URLs before validating the scheme.
- Normalizes CRLF/CR line endings in the wrapper script to LF to avoid `/bin/sh^M` failures.
- Restores executable permission on `android/gradlew` and fails with an actionable Arabic error if that cannot be done.

The preflight is restricted to the app-private staged project and runs before any PRoot command.

## What this does not prove

- It does not provide the missing ARM64 runtime bundle.
- It does not certify that the installed Flutter/JDK/Android SDK can compile on a particular phone.
- No Flutter/Gradle APK build was run in this environment because Flutter SDK, Android SDK and Android build classpath are unavailable here.
