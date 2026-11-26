/// Lightweight, dependency-free command filtering for the mobile command palette.
class EditorCommandPalette {
  const EditorCommandPalette._();

  static List<T> filter<T>(
    List<T> commands, {
    required String query,
    required String Function(T command) searchableText,
    int maximumResults = 40,
  }) {
    final needle = query.trim().toLowerCase();
    if (maximumResults <= 0) return const [];
    if (needle.isEmpty) return commands.take(maximumResults).toList();

    final ranked = <({T command, int score, int index})>[];
    for (var index = 0; index < commands.length; index++) {
      final command = commands[index];
      final value = searchableText(command).toLowerCase();
      final score = _score(needle, value);
      if (score >= 0) ranked.add((command: command, score: score, index: index));
    }
    ranked.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return ranked.take(maximumResults).map((entry) => entry.command).toList();
  }

  static int _score(String needle, String value) {
    if (value == needle) return 0;
    if (value.startsWith(needle)) return 1;
    if (value.split(RegExp(r'\\s+')).any((word) => word.startsWith(needle))) return 2;
    final substring = value.indexOf(needle);
    if (substring >= 0) return 3 + substring;
    var cursor = 0;
    for (var i = 0; i < value.length && cursor < needle.length; i++) {
      if (value[i] == needle[cursor]) cursor++;
    }
    return cursor == needle.length ? 100 : -1;
  }
}
