import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_backup_repository.dart';

void main() {
  const repository = ProjectBackupRepository();

  ProjectBackupSnapshot snapshot(String id, DateTime date) =>
      repository.createSnapshot(
        id: id,
        projectName: 'Demo',
        createdAt: date,
        fileCount: 2,
        directoryCount: 1,
        totalBytes: 20,
        manifestBytes: [1, 2, 3],
      );

  test('catalog round-trip sorts newest snapshot first', () {
    final older = snapshot('older', DateTime.utc(2026, 1, 1));
    final newer = snapshot('newer', DateTime.utc(2026, 1, 2));
    final decoded = repository.decodeCatalog(
      repository.encodeCatalog([older, newer]),
    );

    expect(decoded.map((item) => item.id), ['newer', 'older']);
  });

  test('detects backup manifest corruption', () {
    final item = snapshot('snapshot-1', DateTime.utc(2026, 1, 1));
    expect(repository.verifyManifest(item, [1, 2, 3]), isTrue);
    expect(repository.verifyManifest(item, [1, 2, 4]), isFalse);
  });

  test('rejects unsafe catalog ids and duplicate ids', () {
    expect(
      () => repository.createSnapshot(
        id: '../escape',
        projectName: 'Demo',
        createdAt: DateTime.utc(2026),
        fileCount: 0,
        directoryCount: 0,
        totalBytes: 0,
        manifestBytes: [],
      ),
      throwsArgumentError,
    );
    final item = snapshot('same', DateTime.utc(2026, 1, 1));
    expect(() => repository.encodeCatalog([item, item]), throwsFormatException);
  });

  test('compares backup file sets', () {
    final result = repository.compareFileChecksums(
      older: {'same.dart': 'a', 'changed.dart': 'old', 'removed.dart': 'x'},
      newer: {'same.dart': 'a', 'changed.dart': 'new', 'added.dart': 'z'},
    );
    expect(result.added, ['added.dart']);
    expect(result.removed, ['removed.dart']);
    expect(result.changed, ['changed.dart']);
    expect(result.unchanged, ['same.dart']);
  });
}
