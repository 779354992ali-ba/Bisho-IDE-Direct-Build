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
    final lines = <EditorMinimapLine>[];
    var start = 0;
    var number = 1;
    while (start <= source.length && lines.length < maximumLines) {
      final end = source.indexOf('\n', start);
      final stop = end < 0 ? source.length : end;
      lines.add(EditorMinimapLine(
        number: number++,
        text: source.substring(start, stop).replaceAll('\r', ''),
        startOffset: start,
      ));
      if (end < 0) break;
      start = end + 1;
    }
    return List.unmodifiable(lines);
  }
}
