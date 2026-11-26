import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists non-secret settings used by the GitHub build screen.
/// Personal access tokens are deliberately excluded.
class RemoteBuildSettings {
  const RemoteBuildSettings({
    this.repository = '',
    this.workflow = 'main.yml',
    this.branch = 'main',
    this.flutterVersion = '3.47.9',
  });

  static const preferenceKey = 'bisho_remote_build_settings_v1';

  final String repository;
  final String workflow;
  final String branch;
  final String flutterVersion;

  Map<String, String> toJson() => {
        'repository': repository,
        'workflow': workflow,
        'branch': branch,
        'flutterVersion': flutterVersion,
      };

  factory RemoteBuildSettings.fromJson(Object? value) {
    if (value is! Map) return const RemoteBuildSettings();
    String read(String key, String fallback) {
      final candidate = value[key];
      return candidate is String ? candidate : fallback;
    }

    return RemoteBuildSettings(
      repository: read('repository', ''),
      workflow: read('workflow', 'main.yml'),
      branch: read('branch', 'main'),
      flutterVersion: read('flutterVersion', '3.47.9'),
    );
  }

  static Future<RemoteBuildSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep the typed read inside the recovery boundary: getString itself
      // can throw when an older/corrupted preference was stored as a number,
      // boolean, list, or another incompatible type.
      final encoded = prefs.getString(preferenceKey);
      if (encoded == null || encoded.isEmpty) {
        return const RemoteBuildSettings();
      }
      return RemoteBuildSettings.fromJson(jsonDecode(encoded));
    } catch (_) {
      // Treat unavailable, malformed, or type-incompatible optional
      // preferences as defaults instead of preventing the build screen opening.
      return const RemoteBuildSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, jsonEncode(toJson()));
  }
}
