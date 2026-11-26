import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/build_history_store.dart';

void main() {
  late Directory directory;
  late BuildHistoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bisho-build-history-');
    store = BuildHistoryStore(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('records newest build first and preserves build metadata', () async {
    await store.record(
      log: 'first log',
      success: true,
      mode: 'debug',
      projectName: 'Demo',
    );
    await store.record(
      log: 'second log',
      success: false,
      mode: 'release',
      projectName: 'Demo',
    );

    final entries = await store.recent();
    expect(entries, hasLength(2));
    expect(entries.first['log'], 'second log');
    expect(entries.first['success'], isFalse);
    expect(entries.last['log'], 'first log');
  });

  test('bounds retained build history to fifty entries', () async {
    for (var i = 0; i < 55; i++) {
      await store.record(
        log: 'log-$i',
        success: true,
        mode: 'debug',
        projectName: 'Demo',
      );
    }
    expect(await store.recent(limit: 100), hasLength(50));
  });

  test('truncates oversized logs and clamps requested history limits', () async {
    await store.record(
      log: List<String>.filled(BuildHistoryStore.maxLogCharacters + 10, 'x').join(),
      success: true,
      mode: 'debug',
      projectName: 'Demo',
    );
    final entries = await store.recent(limit: 500);
    expect(entries, hasLength(1));
    expect((entries.single['log'] as String).length,
        lessThan(BuildHistoryStore.maxLogCharacters + 50));
    expect(await store.recent(limit: 0), isEmpty);
    expect(await store.recent(limit: -1), isEmpty);
  });

  test('ignores history files that exceed the storage size limit', () async {
    await directory.create(recursive: true);
    await File('${directory.path}/build_history.json').writeAsString(
      List<String>.filled(BuildHistoryStore.maxHistoryFileBytes + 1, 'x').join(),
    );
    expect(await store.recent(), isEmpty);
    await store.record(
      log: 'fresh log',
      success: true,
      mode: 'debug',
      projectName: 'Demo',
    );
    expect((await store.recent()).single['log'], 'fresh log');
  });

  test('returns an empty history when storage is malformed', () async {
    await directory.create(recursive: true);
    await File('${directory.path}/build_history.json').writeAsString('{bad');
    expect(await store.recent(), isEmpty);
  });
}
