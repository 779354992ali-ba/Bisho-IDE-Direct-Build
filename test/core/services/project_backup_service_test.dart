import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/project_backup_service.dart';

void main() {
  const service = ProjectBackupService();

  test('encodes and decodes files and empty directories', () {
    final encoded = service.encode(
      projectName: 'Demo',
      files: {'lib/main.dart': [1, 2, 3], 'assets/data.bin': [0, 255]},
      directories: ['empty-folder'],
      createdAt: DateTime.utc(2026, 1, 2),
    );
    final decoded = service.decode(encoded);

    expect(decoded.projectName, 'Demo');
    expect(decoded.files['lib/main.dart']!.bytes, [1, 2, 3]);
    expect(decoded.files['assets/data.bin']!.bytes, [0, 255]);
    expect(decoded.directories, contains('empty-folder'));
  });

  test('rejects content whose checksum or declared size was modified', () {
    final encoded = service.encode(projectName: 'Demo', files: {'a.txt': [1, 2, 3]});
    final tampered = encoded.replaceFirst('AQID', 'BAUG');
    expect(() => service.decode(tampered), throwsFormatException);
  });

  test('rejects traversal and absolute paths', () {
    expect(() => service.encode(projectName: 'Demo', files: {'../secret': [1]}),
        throwsFormatException);
    expect(() => service.encode(projectName: 'Demo', files: {'/secret': [1]}),
        throwsFormatException);
  });

  test('rejects duplicate and case-colliding portable paths', () {
    expect(
      () => service.encode(projectName: 'Demo', files: {
        'Lib/main.dart': [1],
        'lib/other.dart': [2],
      }),
      throwsFormatException,
    );
  });

  test('rejects reserved Windows device names', () {
    expect(() => service.encode(projectName: 'Demo', files: {'CON.txt': [1]}),
        throwsFormatException);
  });

  test('rejects unsupported backup versions', () {
    expect(() => service.decode(
      '{"format":"bisho-project-backup","version":99,"projectName":"Demo","createdAt":"2026-01-01T00:00:00Z","directories":[],"files":[]}',
    ), throwsFormatException);
  });
}
