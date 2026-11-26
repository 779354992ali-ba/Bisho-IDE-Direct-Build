import 'dart:convert';
import 'dart:io';

/// Optional, best-effort local history for Flutter build attempts.
class BuildHistoryStore {
  BuildHistoryStore(this.directory);
  final Directory directory;

  static const int maxEntries = 50;
  static const int maxLogCharacters = 200000;

  Future<File> _file() async {
    await directory.create(recursive: true);
    return File('${directory.path}/build_history.json');
  }

  Future<void> record({
    required String log,
    required bool success,
    required String mode,
    required String projectName,
  }) async {
    final file = await _file();
    List<dynamic> entries = [];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) entries = decoded;
      } catch (_) {
        // Recover from a damaged optional history file by starting a new log.
      }
    }
    entries.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      'success': success,
      'mode': mode,
      'projectName': projectName,
      'log': log.length > maxLogCharacters
          ? '${log.substring(0, maxLogCharacters)}\\n… تم اختصار سجل البناء لحفظ المساحة'
          : log,
    });
    if (entries.length > maxEntries) {
      entries = entries.take(maxEntries).toList();
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(file.path);
  }

  Future<List<Map<String, dynamic>>> recent({int limit = 20}) async {
    if (limit <= 0) return const [];
    final boundedLimit = limit.clamp(0, maxEntries);
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded.whereType<Map>().take(boundedLimit)
          .map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
