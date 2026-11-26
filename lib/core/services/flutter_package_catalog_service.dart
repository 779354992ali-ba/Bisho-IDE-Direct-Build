import 'dart:convert';

import 'package:http/http.dart' as http;

/// Read-only pub.dev catalog plus a conservative pubspec.yaml editor.
/// Package installation itself is left to Flutter's package resolver.
class FlutterPackageInfo {
  const FlutterPackageInfo({
    required this.name,
    required this.latestVersion,
    required this.description,
  });

  final String name;
  final String latestVersion;
  final String description;
}

class FlutterPackageCatalogService {
  FlutterPackageCatalogService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<List<String>> searchPackages(String query, {int pageSize = 20}) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final response = await _client.get(
      Uri.https('pub.dev', '/api/search', {
        'q': value,
        'page_size': pageSize.clamp(1, 30).toString(),
      }),
      headers: const {'Accept': 'application/json', 'User-Agent': 'Bisho-IDE'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('تعذر البحث في pub.dev (HTTP ${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['packages'] is! List) {
      throw const FormatException('استجابة البحث من pub.dev غير صالحة.');
    }
    final names = <String>[];
    for (final entry in data['packages'] as List) {
      if (entry is Map && entry['package'] is String) {
        final name = entry['package'] as String;
        if (_validName(name) && !names.contains(name)) names.add(name);
      }
    }
    return names;
  }

  Future<FlutterPackageInfo> packageInfo(String name) async {
    if (!_validName(name)) throw ArgumentError.value(name, 'name', 'اسم حزمة غير صالح.');
    final response = await _client.get(
      Uri.https('pub.dev', '/api/packages/$name'),
      headers: const {'Accept': 'application/json', 'User-Agent': 'Bisho-IDE'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('تعذر جلب معلومات الحزمة $name (HTTP ${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('تفاصيل الحزمة غير صالحة.');
    }
    final latest = data['latest'];
    if (latest is! Map) throw const FormatException('لم يتم العثور على إصدار حديث للحزمة.');
    final version = latest['version']?.toString() ?? '';
    if (!_validVersion(version)) {
      throw StateError('أعاد pub.dev إصدارًا غير صالح للحزمة $name.');
    }
    final pubspec = latest['pubspec'];
    final description = pubspec is Map
        ? pubspec['description']?.toString() ?? ''
        : '';
    return FlutterPackageInfo(
      name: name,
      latestVersion: version,
      description: description,
    );
  }

  static Map<String, String> readDependencies(
    String source, {
    String section = 'dependencies',
  }) {
    final lines = source.split('\n');
    final start = lines.indexWhere((line) =>
        RegExp('^' + RegExp.escape(section) + r':\s*(?:#.*)?$').hasMatch(line));
    if (start < 0) return const {};
    final result = <String, String>{};
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) break;
      final match = RegExp(r'^  ([A-Za-z0-9_]+):\s*(.*?)\s*(?:#.*)?$').firstMatch(line);
      if (match != null) result[match.group(1)!] = match.group(2)!;
    }
    return Map.unmodifiable(result);
  }

  static String addDependency(
    String source, {
    required String name,
    required String version,
    String section = 'dependencies',
  }) {
    if (!_validName(name)) throw ArgumentError.value(name, 'name', 'اسم حزمة غير صالح.');
    if (!_validVersion(version)) throw ArgumentError.value(version, 'version', 'إصدار الحزمة غير صالح.');
    if (!<String>{'dependencies', 'dev_dependencies'}.contains(section)) {
      throw ArgumentError.value(section, 'section', 'قسم pubspec غير مدعوم.');
    }
    final lines = source.split('\n');
    final start = lines.indexWhere((line) =>
        RegExp('^' + RegExp.escape(section) + r':\s*(?:#.*)?$').hasMatch(line));
    final entry = '  $name: ^$version';
    if (start < 0) {
      final prefix = source.isEmpty ? '' : (source.endsWith('\n') ? '' : '\n');
      return '$source${prefix}$section:\n$entry\n';
    }

    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        end = i;
        break;
      }
    }
    final existing = RegExp('^  ' + RegExp.escape(name) + r'\s*:');
    for (var i = start + 1; i < end; i++) {
      if (existing.hasMatch(lines[i])) {
        lines[i] = entry;
        return lines.join('\n');
      }
    }
    lines.insert(end, entry);
    return lines.join('\n');
  }

  static String removeDependency(
    String source, {
    required String name,
    String section = 'dependencies',
  }) {
    if (!_validName(name)) throw ArgumentError.value(name, 'name', 'اسم حزمة غير صالح.');
    final lines = source.split('\n');
    final start = lines.indexWhere((line) =>
        RegExp('^' + RegExp.escape(section) + r':\s*(?:#.*)?$').hasMatch(line));
    if (start < 0) return source;
    final existing = RegExp('^  ' + RegExp.escape(name) + r'\s*:');
    for (var i = start + 1; i < lines.length; i++) {
      if (!lines[i].startsWith(' ') && lines[i].trim().isNotEmpty &&
          !lines[i].trimLeft().startsWith('#')) break;
      if (existing.hasMatch(lines[i])) {
        lines.removeAt(i);
        break;
      }
    }
    return lines.join('\n');
  }

  static bool _validName(String value) =>
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value);

  static bool _validVersion(String value) =>
      RegExp(r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$').hasMatch(value);
}
