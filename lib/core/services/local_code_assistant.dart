import 'editor_symbol_index.dart';
import 'editor_syntax_diagnostics.dart';

enum LocalAssistantTask { explain, diagnose, improve, security }

class LocalAssistantReport {
  const LocalAssistantReport({
    required this.title,
    required this.summary,
    required this.items,
  });

  final String title;
  final String summary;
  final List<String> items;
}

/// Deterministic, offline code review helpers. This is not an LLM and does not
/// send source code or prompts to a remote service.
class LocalCodeAssistant {
  const LocalCodeAssistant._();

  static LocalAssistantReport run({
    required String source,
    required String language,
    required LocalAssistantTask task,
  }) {
    switch (task) {
      case LocalAssistantTask.explain:
        return _explain(source, language);
      case LocalAssistantTask.diagnose:
        return _diagnose(source, language);
      case LocalAssistantTask.improve:
        return _improve(source, language);
      case LocalAssistantTask.security:
        return _security(source);
    }
  }

  static LocalAssistantReport _explain(String source, String language) {
    final symbols = EditorSymbolIndex.scan(source, language: language);
    final lines = source.isEmpty ? 0 : source.split('\n').length;
    final imports = RegExp(r'^\s*(?:import|export)\s+', multiLine: true)
        .allMatches(source).length;
    final classes = symbols.where((item) => item.kind == 'class').length;
    final functions = symbols.where((item) =>
        item.kind == 'function' || item.kind == 'method').length;
    final items = symbols.take(14).map((item) =>
        '${item.kind}: ${item.name} — السطر ${item.line}').toList();
    if (items.isEmpty) items.add('لم يتم اكتشاف تعريفات معروفة في الملف.');
    return LocalAssistantReport(
      title: 'شرح بنية الملف',
      summary: 'ملف $language يحتوي على $lines سطرًا و$imports استيرادًا تقريبًا، '
          '$classes صنفًا و$functions دالة/طريقة وفق الفهرسة النصية.',
      items: items,
    );
  }

  static LocalAssistantReport _diagnose(String source, String language) {
    final diagnostics = EditorSyntaxDiagnostics.analyze(source, language);
    final items = diagnostics.take(30).map((item) => item.toString()).toList();
    return LocalAssistantReport(
      title: 'فحص الأخطاء البنيوية',
      summary: diagnostics.isEmpty
          ? 'لم يرصد الفاحص البنيوي أقواسًا غير متطابقة. هذا ليس بديلاً عن compiler أو analyzer.'
          : 'تم العثور على ${diagnostics.length} ملاحظة بنيوية محتملة.',
      items: items.isEmpty ? ['لا توجد ملاحظات بنيوية حالياً.'] : items,
    );
  }

  static LocalAssistantReport _improve(String source, String language) {
    final items = <String>[];
    final lines = source.split('\n');
    final longLines = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].length > 120) longLines.add(i + 1);
    }
    if (longLines.isNotEmpty) {
      items.add('راجع الأسطر الطويلة (>120 محرف): ${longLines.take(12).join(', ')}.');
    }
    final todos = RegExp(r'\b(TODO|FIXME|XXX)\b', caseSensitive: false)
        .allMatches(source).length;
    if (todos > 0) items.add('يوجد $todos تعليق صيانة TODO/FIXME يحتاج إلى متابعة.');
    if (RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}').hasMatch(source) ||
        RegExp(r'catch\s*\{\s*\}').hasMatch(source)) {
      items.add('يوجد catch فارغ؛ أضف معالجة أو تسجيلًا واضحًا للخطأ.');
    }
    if (language == 'Dart' &&
        RegExp(r'\bprint\s*\(').hasMatch(source)) {
      items.add('في تطبيق Flutter، فضّل debugPrint أو نظام تسجيل مضبوطاً على print.');
    }
    final duplicateImports = _duplicateImportCount(source);
    if (duplicateImports > 0) {
      items.add('يمكن إزالة $duplicateImports استيرادًا مكررًا.');
    }
    return LocalAssistantReport(
      title: 'اقتراحات تحسين',
      summary: items.isEmpty
          ? 'لم تظهر قواعد التحسين السريعة ملاحظات واضحة.'
          : 'اقتراحات محلية مبنية على قواعد ثابتة؛ راجعها قبل التطبيق.',
      items: items.isEmpty ? ['الكود لا يحتوي على مؤشرات التحسين المعروفة حالياً.'] : items,
    );
  }

  static LocalAssistantReport _security(String source) {
    final items = <String>[];
    final patterns = <({RegExp pattern, String message})>[
      (pattern: RegExp(r'(?i)(?:ghp_|github_pat_)[A-Za-z0-9_]{12,}'),
        message: 'قد يحتوي الملف على رمز وصول GitHub؛ لا تعرضه أو ترفعه، وانقله إلى التخزين الآمن ثم ألغِ الرمز المكشوف.'),
      (pattern: RegExp(r'(?i)(?:api[_-]?key|secret|password|token)\s*[:=]\s*[\x27\x22][^\x27\x22]{6,}[\x27\x22]'),
        message: 'قد توجد قيمة اعتماد ثابتة داخل المصدر؛ استخدم تخزينًا آمنًا أو متغيرات بيئة.'),
      (pattern: RegExp(r'http://[^\s\x27\x22]+'),
        message: 'راجع روابط HTTP غير المشفرة؛ استخدم HTTPS عندما يكون مدعومًا.'),
    ];
    for (final entry in patterns) {
      if (entry.pattern.hasMatch(source)) items.add(entry.message);
    }
    return LocalAssistantReport(
      title: 'فحص مؤشرات الأمان',
      summary: items.isEmpty
          ? 'لم يتم العثور على الأنماط المحددة للبيانات الحساسة أو روابط HTTP.'
          : 'تم العثور على ${items.length} مؤشر يحتاج إلى مراجعة يدوية.',
      items: items.isEmpty ? ['لا توجد مؤشرات مطابقة للقواعد الحالية.'] : items,
    );
  }

  static int _duplicateImportCount(String source) {
    final seen = <String>{};
    var duplicates = 0;
    final pattern = RegExp(r'^\s*import\s+[\x27\x22]([^\x27\x22]+)[\x27\x22]',
        multiLine: true);
    for (final match in pattern.allMatches(source)) {
      if (!seen.add(match.group(1)!)) duplicates++;
    }
    return duplicates;
  }
}
