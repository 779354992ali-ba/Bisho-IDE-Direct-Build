import 'editor_syntax_diagnostics.dart';

class EditorQuickFixPreview {
  const EditorQuickFixPreview({
    required this.source,
    required this.updatedSource,
    required this.fixes,
  });

  final String source;
  final String updatedSource;
  final List<String> fixes;

  bool get hasChanges => source != updatedSource;
}

/// Offers conservative edits only when the structural repair is unambiguous.
class EditorQuickFixEngine {
  const EditorQuickFixEngine._();

  static EditorQuickFixPreview preview(String source, String language) {
    if (source.isEmpty) {
      return const EditorQuickFixPreview(
        source: '',
        updatedSource: '',
        fixes: [],
      );
    }
    var updated = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final fixes = <String>[];
    final diagnostics = EditorSyntaxDiagnostics.analyze(updated, language);
    final sourceIsNormalized = source.endsWith('\n') &&
        !source.contains('\r') &&
        source.split('\n').every((line) => line == line.trimRight());
    if (diagnostics.isEmpty && sourceIsNormalized) {
      return EditorQuickFixPreview(
        source: source,
        updatedSource: source,
        fixes: const [],
      );
    }

    final unmatchedOpen = diagnostics.where((item) =>
      item.message.startsWith('قوس الفتح')
    ).toList();
    final unmatchedClose = diagnostics.where((item) =>
      item.message.startsWith('قوس إغلاق')
    ).toList();
    final onlyUnmatchedOpen = diagnostics.length == unmatchedOpen.length &&
        unmatchedOpen.isNotEmpty;
    final onlyUnmatchedClose = diagnostics.length == unmatchedClose.length &&
        unmatchedClose.length == 1;

    if (onlyUnmatchedOpen) {
      final closers = unmatchedOpen.reversed.map((item) {
        final match = RegExp(r'قوس الفتح "(.+?)" بلا إغلاق "(.+?)"')
            .firstMatch(item.message);
        return match?.group(2) ?? '';
      }).join();
      if (closers.isNotEmpty) {
        updated = '$updated$closers';
        fixes.add('إضافة أقواس الإغلاق الناقصة: $closers');
      }
    } else if (onlyUnmatchedClose) {
      final offset = unmatchedClose.single.offset;
      if (offset >= 0 && offset < updated.length) {
        final removed = updated[offset];
        updated = updated.replaceRange(offset, offset + 1, '');
        fixes.add('إزالة قوس الإغلاق الزائد: $removed');
      }
    }

    final normalizedLines = updated.split('\n')
        .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
        .toList();
    while (normalizedLines.length > 1 &&
        normalizedLines[normalizedLines.length - 1].isEmpty &&
        normalizedLines[normalizedLines.length - 2].isEmpty) {
      normalizedLines.removeLast();
    }
    updated = normalizedLines.isEmpty ? '' : '${normalizedLines.join('\n')}\n';
    if (updated != source && !fixes.any((item) => item.contains('مسافات'))) {
      if (source.contains('\r') || source.split('\n').any((line) => line.endsWith(' '))) {
        fixes.add('توحيد نهايات الأسطر وإزالة المسافات الزائدة');
      } else if (!source.isEmpty && !source.endsWith('\n')) {
        fixes.add('إضافة سطر نهائي للملف');
      }
    }
    if (fixes.isEmpty && updated != source) {
      fixes.add('توحيد تنسيق نهايات الأسطر والمسافات');
    }
    return EditorQuickFixPreview(
      source: source,
      updatedSource: updated,
      fixes: List.unmodifiable(fixes),
    );
  }
}
