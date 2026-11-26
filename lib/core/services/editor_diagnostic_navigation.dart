/// Maps a 1-based diagnostic line/column to a safe UTF-16 text offset.
class EditorDiagnosticNavigation {
  const EditorDiagnosticNavigation._();

  static int? offsetForLineColumn(String source, int line, int column) {
    if (line < 1 || column < 1) return null;
    var currentLine = 1;
    var lineStart = 0;

    for (var i = 0; i < source.length && currentLine < line; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        currentLine++;
        lineStart = i + 1;
      }
    }
    if (currentLine != line) return null;

    var lineEnd = source.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = source.length;
    if (lineEnd > lineStart && source.codeUnitAt(lineEnd - 1) == 0x0D) {
      lineEnd--;
    }
    final requested = lineStart + column - 1;
    return requested.clamp(lineStart, lineEnd).toInt();
  }
}
