import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_command_palette.dart';

void main() {
  group('EditorCommandPalette.filter', () {
    const commands = <String>[
      'Open File — open a file',
      'Format Document — format source code',
      'Find in Project — search all files',
      'Flutter Build — start a build',
      'File History — restore a previous version',
    ];

    test('ranks exact and whole-word prefixes ahead of substrings', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: 'file',
        searchableText: (command) => command,
      );

      expect(result.first, 'File History — restore a previous version');
      expect(result[1], 'Open File — open a file');
    });

    test('matches the beginning of any whitespace-delimited word', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: 'restore',
        searchableText: (command) => command,
      );

      expect(result, ['File History — restore a previous version']);
    });

    test('supports substring and fuzzy matches without losing stable order', () {
      final result = EditorCommandPalette.filter(
        const ['alpha beta', 'find by directory', 'file backup details'],
        query: 'fbd',
        searchableText: (command) => command,
      );

      expect(result, ['find by directory', 'file backup details']);
    });

    test('trims and ignores query case', () {
      final result = EditorCommandPalette.filter(
        commands,
        query: '  FLUTTER ',
        searchableText: (command) => command,
      );

      expect(result, ['Flutter Build — start a build']);
    });

    test('honours the maximum result count including non-positive limits', () {
      expect(
        EditorCommandPalette.filter(
          commands,
          query: '',
          searchableText: (command) => command,
          maximumResults: 2,
        ),
        commands.take(2),
      );
      expect(
        EditorCommandPalette.filter(
          commands,
          query: 'file',
          searchableText: (command) => command,
          maximumResults: 0,
        ),
        isEmpty,
      );
    });
  });
}
