# Package87 validation report

- ZIP integrity (`unzip -t`): passed; all entries readable.
- Package root and required Package87 changelog/report entries: passed.
- `pubspec.yaml` parsed successfully with PyYAML; version is `1.0.0+87`.
- `android/app/src/main/AndroidManifest.xml` parsed successfully as XML.
- `bash -n tools/engine_bundle/validate_and_pack.sh`: passed.
- Kotlin compiler parser pass: no Kotlin syntax/parser diagnostics. Full Kotlin compilation is unavailable because Android and Flutter embedding dependencies are not installed in this environment; unresolved platform symbols are expected.
- Isolated Kotlin behavior check: escaped Gradle `distributionUrl` (`https\\://...`) is normalized to HTTPS, and CRLF wrapper lines are normalized to LF; passed.
- Flutter analyze/tests: not run (Flutter SDK unavailable).
- Gradle/Android compilation: not run (Android SDK/Gradle Android classpath unavailable).
- End-to-end on-device APK build: not run; no real ARM64 engine archive or Android device is available in this environment.
