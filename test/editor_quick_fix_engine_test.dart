import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_quick_fix_engine.dart';

void main() {
  group('EditorQuickFixEngine', () {
    test('closes a single unmatched opening brace', () {
      final preview = EditorQuickFixEngine.preview('void main() {', 'Dart');
      expect(preview.hasChanges, isTrue);
      expect(preview.updatedSource, 'void main() {}\n');
      expect(preview.fixes.join(' '), contains('أقواس الإغلاق'));
    });

    test('removes a single unmatched closing delimiter', () {
      final preview = EditorQuickFixEngine.preview('void main() {} )', 'Dart');
      expect(preview.updatedSource, 'void main() {} \n');
      expect(preview.fixes.join(' '), contains('قوس الإغلاق الزائد'));
    });

    test('normalizes whitespace and line endings', () {
      final preview = EditorQuickFixEngine.preview('a  \r\nb', 'Dart');
      expect(preview.updatedSource, 'a\nb\n');
      expect(preview.fixes, isNotEmpty);
    });

    test('does not guess when delimiters are mismatched', () {
      final source = 'void main() {]';
      final preview = EditorQuickFixEngine.preview(source, 'Dart');
      expect(preview.updatedSource, isNot(contains('}')));
    });

    test('returns no changes for normalized source', () {
      final preview = EditorQuickFixEngine.preview('void main() {}\n', 'Dart');
      expect(preview.hasChanges, isFalse);
      expect(preview.fixes, isEmpty);
    });
  });
}
