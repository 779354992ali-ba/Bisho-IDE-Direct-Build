/// Safe, deterministic text replacement used by project-wide refactoring.
class ProjectTextReplacement {
  const ProjectTextReplacement._();

  static ({String text, int replacements}) replaceAll({
    required String source,
    required String query,
    required String replacement,
    bool caseSensitive = true,
  }) {
    if (query.isEmpty) return (text: source, replacements: 0);
    if (caseSensitive) {
      final matches = query.allMatches(source).length;
      return (
        text: matches == 0 ? source : source.replaceAll(query, replacement),
        replacements: matches,
      );
    }

    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final output = StringBuffer();
    var cursor = 0;
    var count = 0;
    while (true) {
      final match = lowerSource.indexOf(lowerQuery, cursor);
      if (match < 0) break;
      output
        ..write(source.substring(cursor, match))
        ..write(replacement);
      cursor = match + query.length;
      count++;
    }
    output.write(source.substring(cursor));
    return (text: count == 0 ? source : output.toString(), replacements: count);
  }
}
