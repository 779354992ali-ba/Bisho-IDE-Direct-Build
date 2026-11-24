import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_extension_manifest.dart';

void main() {
  Map<String, Object?> pack(List<Object?> extensions) => {
    'format': EditorExtensionManifest.format,
    'version': EditorExtensionManifest.version,
    'extensions': extensions,
  };

  Map<String, Object?> entry({
    String id = 'json_pretty',
    String operation = 'json_format',
  }) => {
    'id': id,
    'title': 'JSON مرتب',
    'description': 'تنسيق JSON بسرعة',
    'category': 'تنسيق',
    'operation': operation,
  };

  test('accepts a valid declarative pack with a built-in operation', () {
    final manifest = EditorExtensionManifest.decode(
      jsonEncode(pack([entry()])),
    );
    expect(manifest.extensions, hasLength(1));
    expect(manifest.extensions.single.operation, 'json_format');
  });

  test('rejects duplicate extension identifiers', () {
    expect(
      () => EditorExtensionManifest.decode(
        jsonEncode(pack([entry(), entry(operation: 'json_minify')])),
      ),
      throwsFormatException,
    );
  });

  test('rejects unknown operations instead of executing external code', () {
    expect(
      () => EditorExtensionManifest.decode(
        jsonEncode(pack([entry(operation: 'run_shell')])),
      ),
      throwsFormatException,
    );
  });

  test('rejects path-like or malformed identifiers', () {
    expect(
      () => EditorExtensionManifest.decode(
        jsonEncode(pack([entry(id: '../payload')])),
      ),
      throwsFormatException,
    );
  });

  test('rejects unsupported manifest versions', () {
    final invalid = pack([entry()])..['version'] = 99;
    expect(
      () => EditorExtensionManifest.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  test('rejects oversized extension packs', () {
    expect(
      () => EditorExtensionManifest.decode('x' * (64 * 1024 + 1)),
      throwsFormatException,
    );
  });

  test('rejects empty packs and oversized extension lists', () {
    expect(
      () => EditorExtensionManifest.decode(jsonEncode(pack([]))),
      throwsFormatException,
    );
    expect(
      () => EditorExtensionManifest.decode(
        jsonEncode(pack(List.generate(31, (i) => entry(id: 'ext_$i')))),
      ),
      throwsFormatException,
    );
  });
}
