# Bisho IDE Package87

Package87 hardens the local Android build preflight after SAF project import. The most important change restores executable permission to `android/gradlew`, normalizes its line endings, and validates the Gradle wrapper JAR and distribution URL before Flutter invokes Gradle inside PRoot.

See `PACKAGE87_CHANGELOG.md` and `PACKAGE87_TEST_REPORT.md` for details and validation limits.

**Important:** Package87 is a code update, not a bundled Linux/Flutter/JDK/Android SDK engine. Actual local APK production remains unverified until a compatible ARM64 engine bundle is installed and tested on a supported Android phone.
