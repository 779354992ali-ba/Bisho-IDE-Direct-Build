class EditorMinimapLine {
  const EditorMinimapLine({
    required this.number,
    required this.text,
    required this.startOffset,
  });

  final int number;
  final String text;
  final int startOffset;
}

/// Compact, bounded line model for the editor minimap.
class EditorMinimapModel {
  const EditorMinimapModel._();

  static List<EditorMinimapLine> fromText(
    String source, {
    int maximumLines = 500,
  }) {
    if (source.isEmpty || maximumLines <= 0) return const [];

    // The minimap displays normalized line endings, so its offsets must use
    // the same coordinate space (CRLF and lone CR both become one LF).
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = <EditorMinimapLine>[];
    var start = 0;
    var number = 1;
    while (start <= normalized.length && lines.length < maximumLines) {
      final end = normalized.indexOf('\n', start);
      final stop = end < 0 ? normalized.length : end;
      lines.add(EditorMinimapLine(
        number: number++,
        text: normalized.substring(start, stop),
        startOffset: start,
      ));
      if (end < 0) break;
      start = end + 1;
    }
    return List.unmodifiable(lines);
  }
}
