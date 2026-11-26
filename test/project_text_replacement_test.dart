import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_text_replacement.dart';

void main() {
  group('ProjectTextReplacement', () {
    test('replaces every exact match and reports count', () {
      final result = ProjectTextReplacement.replaceAll(
        source: 'foo bar foo',
        query: 'foo',
        replacement: 'baz',
      );
      expect(result.text, 'baz bar baz');
      expect(result.replacements, 2);
    });

    test('supports case-insensitive replacement without changing other text', () {
      final result = ProjectTextReplacement.replaceAll(
        source: 'Foo foo FOO',
        query: 'foo',
        replacement: 'x',
        caseSensitive: false,
      );
      expect(result.text, 'x x x');
      expect(result.replacements, 3);
    });

    test('empty or missing query leaves source unchanged', () {
      for (final query in ['', 'missing']) {
        final result = ProjectTextReplacement.replaceAll(
          source: 'keep me',
          query: query,
          replacement: 'changed',
        );
        expect(result.text, 'keep me');
        expect(result.replacements, 0);
      }
    });

    test('replacement text is not searched again', () {
      final result = ProjectTextReplacement.replaceAll(
        source: 'a a',
        query: 'a',
        replacement: 'aa',
      );
      expect(result.text, 'aa aa');
      expect(result.replacements, 2);
    });
  });
}
