import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_health_analyzer.dart';

void main() {
  const analyzer = ProjectHealthAnalyzer();

  test('reports missing Flutter source and Android scaffold entries', () {
    final issues = analyzer.analyze(
      paths: {'pubspec.yaml', 'android/', 'lib/'},
      pubspecContent: 'dependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final paths = issues.map((issue) => issue.path).toSet();
    expect(paths, contains('lib/main.dart'));
    expect(paths, contains('analysis_options.yaml'));
    expect(paths, contains('.metadata'));
    expect(paths, contains('test/widget_test.dart'));
    expect(paths, contains('android/app/src/debug/AndroidManifest.xml'));
    expect(paths, contains('android/app/src/profile/AndroidManifest.xml'));
    expect(paths, contains('android/app/src/main/res/drawable/launch_background.xml'));
    expect(paths, contains('android/app/src/main/res/drawable/ic_launcher.xml'));
    expect(paths, contains('.github/workflows/build-android.yml'));
    expect(paths, contains('android/settings.gradle'));
    expect(paths, contains('android/app/src/main/AndroidManifest.xml'));
    expect(issues.every((issue) => issue.repairable), isTrue);
  });

  test('accepts an existing workflow regardless of its filename', () {
    final issues = analyzer.analyze(
      paths: {
        'pubspec.yaml',
        'lib/main.dart',
        'analysis_options.yaml',
        '.github/workflows/main.yml',
      },
      pubspecContent: 'dependencies:\n  flutter:\n    sdk: flutter\n',
    );
    expect(issues.any((issue) => issue.code == 'missing_android_workflow'), isFalse);
  });

  test('does not classify a non-Flutter pubspec as Flutter', () {
    final issues = analyzer.analyze(
      paths: {'pubspec.yaml'},
      pubspecContent: 'name: sample\ndependencies:\n  http: ^1.0.0\n',
    );
    expect(issues, isEmpty);
  });

  test('does not report an existing Flutter entry point', () {
    final issues = analyzer.analyze(
      paths: {'pubspec.yaml', 'lib/', 'lib/main.dart'},
      pubspecContent: 'dependencies:\n  flutter:\n    sdk: flutter\n',
    );
    expect(issues.any((issue) => issue.path == 'lib/main.dart'), isFalse);
  });
}
