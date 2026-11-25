import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bisho_ide/core/services/remote_build_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteBuildSettings', () {
    test('uses safe defaults when no settings were saved', () async {
      final settings = await RemoteBuildSettings.load();

      expect(settings.repository, isEmpty);
      expect(settings.workflow, 'main.yml');
      expect(settings.branch, 'main');
      expect(settings.flutterVersion, '3.47.9');
    });

    test('round-trips repository, workflow, branch and Flutter version', () async {
      const expected = RemoteBuildSettings(
        repository: 'owner/project',
        workflow: 'android.yml',
        branch: 'release',
        flutterVersion: '3.47.9',
      );

      await expected.save();
      final actual = await RemoteBuildSettings.load();

      expect(actual.toJson(), expected.toJson());
    });

    test('ignores malformed persisted JSON and restores defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(RemoteBuildSettings.preferenceKey, '{broken');

      final settings = await RemoteBuildSettings.load();

      expect(settings.toJson(), const RemoteBuildSettings().toJson());
    });

    test('does not serialize or restore credentials', () async {
      const settings = RemoteBuildSettings(repository: 'owner/project');
      expect(settings.toJson().containsKey('token'), isFalse);
      expect(settings.toJson().containsKey('personalAccessToken'), isFalse);
    });
  });
}
