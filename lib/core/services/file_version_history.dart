import 'dart:convert';
import 'dart:io';

/// Small, bounded local snapshots. Callers treat this service as optional.
class FileVersionHistory {
  FileVersionHistory(this.directory);
  final Directory directory;

  String _safeName(String key) {
    final bytes = utf8.encode(key);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<File> _file(String key) async {
    await directory.create(recursive: true);
    return File('${directory.path}/${_safeName(key)}.json');
  }

  Future<void> snapshot(
    String key,
    String fileName,
    String content, {
    String label = 'حفظ',
  }) async {
    final file = await _file(key);
    List<dynamic> entries = [];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) entries = decoded;
      } catch (_) {}
    }
    // Avoid storing identical consecutive snapshots.
    if (entries.isNotEmpty && entries.first is Map &&
        entries.first['content'] == content) return;
    entries.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      'fileName': fileName,
      'label': label,
      'content': content,
    });
    if (entries.length > 30) entries = entries.take(30).toList();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(file.path);
  }

  Future<List<Map<String, dynamic>>> list(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
