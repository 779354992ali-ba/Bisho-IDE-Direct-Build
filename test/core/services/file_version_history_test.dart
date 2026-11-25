import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/file_version_history.dart';

void main() {
  late Directory directory;
  late FileVersionHistory history;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bisho-file-versions-');
    history = FileVersionHistory(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('stores snapshots and returns newest first', () async {
    await history.snapshot('project|main.dart', 'main.dart', 'old');
    await history.snapshot('project|main.dart', 'main.dart', 'new');

    final entries = await history.list('project|main.dart');
    expect(entries, hasLength(2));
    expect(entries.first['content'], 'new');
    expect(entries.last['content'], 'old');
  });

  test('does not duplicate identical consecutive snapshots', () async {
    await history.snapshot('project|main.dart', 'main.dart', 'same');
    await history.snapshot('project|main.dart', 'main.dart', 'same');
    expect(await history.list('project|main.dart'), hasLength(1));
  });

  test('keeps at most thirty snapshots per file', () async {
    for (var i = 0; i < 35; i++) {
      await history.snapshot('project|main.dart', 'main.dart', 'version-$i');
    }
    expect(await history.list('project|main.dart'), hasLength(30));
  });

  test('isolates history by file key', () async {
    await history.snapshot('project|a.dart', 'a.dart', 'A');
    await history.snapshot('project|b.dart', 'b.dart', 'B');
    expect((await history.list('project|a.dart')).single['content'], 'A');
    expect((await history.list('project|b.dart')).single['content'], 'B');
  });
}
