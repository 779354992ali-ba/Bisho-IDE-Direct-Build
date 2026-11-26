import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_archive_validator.dart';

void main() {
  group('ProjectArchiveValidator', () {
    test('normalizes safe Windows separators', () {
      expect(ProjectArchiveValidator.normalizePath(r'lib\src\main.dart'),
          'lib/src/main.dart');
    });

    test('rejects traversal, absolute, drive and null-byte paths', () {
      for (final path in ['../secret', 'lib/../../secret', '/etc/passwd',
        r'C:\secret.txt', 'lib/\u0000bad.dart']) {
        expect(() => ProjectArchiveValidator.normalizePath(path),
            throwsFormatException, reason: path);
      }
    });

    test('enforces entry and byte budgets', () {
      expect(
        () => ProjectArchiveValidator.validateArchive(entryCount: 0, files: const []),
        throwsFormatException,
      );
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

    test('rejects duplicate and case-colliding paths', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(['lib/main.dart', 'lib/main.dart']),
        throwsFormatException,
      );
      expect(
        () => ProjectArchiveValidator.validateFilePaths(['Lib/main.dart', 'lib/other.dart']),
        throwsFormatException,
      );
    });

    test('rejects file-directory prefix collisions', () {
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib', 'lib/main.dart'],
        ),
        throwsFormatException,
      );
      expect(
        () => ProjectArchiveValidator.validateFilePaths(
          ['lib/main.dart'],
          directoryPaths: ['lib/main.dart'],
        ),
        throwsFormatException,
      );
    });
  });

  group('ProjectArchiveBudget', () {
    test('rejects duplicate export paths', () {
      final budget = ProjectArchiveBudget();
      budget.registerEntry('lib/main.dart', byteCount: 10);
      expect(() => budget.registerEntry('lib/main.dart', byteCount: 10),
          throwsFormatException);
    });

    test('rejects case-insensitive export collisions', () {
      final budget = ProjectArchiveBudget();
      budget.registerEntry('Assets/logo.png', byteCount: 10);
      expect(() => budget.registerEntry('assets/logo.png', byteCount: 10),
          throwsFormatException);
    });
  });
}
