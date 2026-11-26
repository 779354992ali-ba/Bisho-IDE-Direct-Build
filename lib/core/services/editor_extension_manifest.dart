import 'dart:convert';

/// Validates declarative Bisho extension packs.
///
/// Packs may reference built-in operations only. They cannot ship or execute
/// Dart, JavaScript, shell commands, native code, or arbitrary permissions.
class EditorExtensionManifestEntry {
  const EditorExtensionManifestEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.operation,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String operation;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'operation': operation,
  };
}

class EditorExtensionManifest {
  const EditorExtensionManifest._(this.extensions);

  static const format = 'bisho-extension-pack';
  static const version = 1;
  static const maxExtensions = 30;
  static const maxTextLength = 120;
  static const supportedOperations = <String>{
    'json_format',
    'json_minify',
    'base64_encode',
    'base64_decode',
    'url_encode',
    'url_decode',
    'sort_lines',
    'unique_lines',
    'trim_trailing_whitespace',
    'normalize_line_endings',
    'tabs_to_spaces',
  };

  final List<EditorExtensionManifestEntry> extensions;

  factory EditorExtensionManifest.decode(String source) {
    if (source.length > 64 * 1024) {
      throw const FormatException('حزمة الإضافات أكبر من الحد المسموح (64KB).');
    }
    final Object? decoded;
    try {
      decoded = _decodeJson(source);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('ملف حزمة الإضافات ليس JSON صالحاً.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['version'] != version ||
        decoded['extensions'] is! List) {
      throw const FormatException('صيغة حزمة الإضافات غير مدعومة.');
    }

    final rawEntries = decoded['extensions'] as List;
    if (rawEntries.isEmpty || rawEntries.length > maxExtensions) {
      throw const FormatException('يجب أن تحتوي الحزمة على 1 إلى 30 إضافة.');
    }
    final ids = <String>{};
    final entries = <EditorExtensionManifestEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('يوجد سجل إضافة غير صالح.');
      }
      final id = raw['id'];
      final title = raw['title'];
      final description = raw['description'];
      final category = raw['category'];
      final operation = raw['operation'];
      if (id is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(id) ||
          !ids.add(id) ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > maxTextLength ||
          description is! String ||
          description.length > maxTextLength ||
          category is! String ||
          category.trim().isEmpty ||
          category.length > maxTextLength ||
          operation is! String ||
          !supportedOperations.contains(operation)) {
        throw const FormatException(
          'بيانات إضافة غير صالحة أو عملية غير مدعومة. لا يُسمح بتنفيذ كود خارجي.',
        );
      }
      entries.add(EditorExtensionManifestEntry(
        id: id,
        title: title.trim(),
        description: description.trim(),
        category: category.trim(),
        operation: operation,
      ));
    }
    return EditorExtensionManifest._(List.unmodifiable(entries));
  }

  static Object? _decodeJson(String source) {
    // Kept local to avoid adding a runtime or code-execution dependency.
    return jsonDecode(source);
  }
}
