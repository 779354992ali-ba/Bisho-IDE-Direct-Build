import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_command_palette.dart';

void main() {
  group('EditorCommandPalette', () {
    const commands = ['Open Project', 'Create File', 'Save All', 'Search in Files'];

    test('prioritizes exact and prefix matches', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: 'save',
        searchableText: (value) => value,
      );
      expect(result.first, 'Save All');
    });

    test('matches words and fuzzy subsequences', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: 'prj',
        searchableText: (value) => value,
      );
      expect(result, contains('Open Project'));
    });

    test('ignores case and surrounding whitespace', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: '  FILES ',
        searchableText: (value) => value,
      );
      expect(result, contains('Search in Files'));
    });

    test('returns bounded results and handles empty queries', () {
      expect(EditorCommandPalette.filter(
        commands,
        query: '',
        searchableText: (value) => value,
        maximumResults: 2,
      ), hasLength(2));
      expect(EditorCommandPalette.filter(
        commands,
        query: 'not-found',
        searchableText: (value) => value,
      ), isEmpty);
    });
  });
}
