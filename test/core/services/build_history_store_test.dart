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

  test('returns an empty history when storage is malformed', () async {
    await directory.create(recursive: true);
    await File('${directory.path}/build_history.json').writeAsString('{bad');
    expect(await store.recent(), isEmpty);
  });
}
