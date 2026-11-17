import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_archive_validator.dart';

void main() {
  group('ProjectArchiveValidator', () {
    test('normalizes nested relative paths', () {
      expect(ProjectArchiveValidator.normalizePath(r'lib\\src\\main.dart'),
          'lib/src/main.dart');
    });

    test('rejects traversal and absolute paths', () {
      expect(() => ProjectArchiveValidator.normalizePath('../outside'),
          throwsFormatException);
      expect(() => ProjectArchiveValidator.normalizePath('/system/file'),
          throwsFormatException);
      expect(() => ProjectArchiveValidator.normalizePath(r'C:\\temp\\file'),
          throwsFormatException);
    });

    test('rejects duplicate file paths', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib/main.dart', 'lib/main.dart'],
        ),
        throwsFormatException,
      );
    });

    test('rejects file and directory path collisions', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib', 'lib/main.dart'],
        ),
        throwsFormatException,
      );
    });


    test('rejects file paths that differ only by letter case', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib/Main.dart', 'LIB/main.dart'],
        ),
        throwsFormatException,
      );
    });

    test('rejects parent directories that differ only by letter case', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['Lib/main.dart', 'lib/helper.dart'],
        ),
        throwsFormatException,
      );
    });

    test('rejects file and parent directory collisions regardless of case', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['Lib', 'lib/main.dart'],
        ),
        throwsFormatException,
      );
    });


    test('rejects explicit ZIP directories that differ from file parent casing', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib/main.dart'],
          directoryPaths: ['LIB/'],
        ),
        throwsFormatException,
      );
    });

    test('rejects a ZIP file path that collides with an explicit directory', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['assets'],
          directoryPaths: ['ASSETS/'],
        ),
        throwsFormatException,
      );
    });

    test('accepts independent nested files', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib/main.dart', 'assets/logo.png'],
        ),
        returnsNormally,
      );
    });


    test('enforces ZIP export budgets incrementally and rejects duplicate paths', () {
      final budget = ProjectArchiveBudget();
      budget.registerEntry('lib', byteCount: 0);
      budget.registerEntry('lib/main.dart', byteCount: 12);
      expect(budget.entryCount, 2);
      expect(budget.totalBytes, 12);
      expect(
        () => budget.registerEntry('lib/main.dart', byteCount: 1),
        throwsFormatException,
      );
    });


    test('export budget rejects paths that differ only by letter case', () {
      final budget = ProjectArchiveBudget();
      budget.registerEntry('lib/Main.dart', byteCount: 1);
      expect(
        () => budget.registerEntry('LIB/main.dart', byteCount: 1),
        throwsFormatException,
      );
    });

    test('rejects oversized files and total export size before archiving', () {
      final fileBudget = ProjectArchiveBudget();
      expect(
        () => fileBudget.registerEntry(
          'large.bin',
          byteCount: ProjectArchiveValidator.maxSingleFileBytes + 1,
        ),
        throwsFormatException,
      );
      final totalBudget = ProjectArchiveBudget();
      for (var index = 0; index < 4; index++) {
        totalBudget.registerEntry(
          'part$index.bin',
          byteCount: ProjectArchiveValidator.maxSingleFileBytes,
        );
      }
      expect(
        () => totalBudget.registerEntry('overflow.bin', byteCount: 1),
        throwsFormatException,
      );
    });

    test('rejects excessive archive entry count and expanded size', () {
      expect(
        () => ProjectArchiveValidator.validateArchive(
          entryCount: ProjectArchiveValidator.maxEntries + 1,
          files: const [],
        ),
        throwsFormatException,
      );
      expect(
        () => ProjectArchiveValidator.validateArchive(
          entryCount: 1,
          files: [MapEntry('large.bin', ProjectArchiveValidator.maxSingleFileBytes + 1)],
        ),
        throwsFormatException,
      );
    });
  });
}
