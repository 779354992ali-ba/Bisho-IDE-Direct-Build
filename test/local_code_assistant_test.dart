import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/local_code_assistant.dart';

void main() {
  group('LocalCodeAssistant', () {
    test('explains file structure using local symbol indexing', () {
      final report = LocalCodeAssistant.run(
        source: 'class Home {}\nvoid main() {}',
        language: 'Dart',
        task: LocalAssistantTask.explain,
      );
      expect(report.title, 'شرح بنية الملف');
      expect(report.summary, contains('1 صنف'));
      expect(report.items.join(' '), contains('Home'));
    });

    test('reports structural diagnostics without claiming compilation', () {
      final report = LocalCodeAssistant.run(
        source: 'void main() {',
        language: 'Dart',
        task: LocalAssistantTask.diagnose,
      );
      expect(report.summary, contains('ملاحظة'));
      expect(report.items.join(' '), contains('قوس'));
    });

    test('suggests improvements for TODO, long lines and empty catch', () {
      final report = LocalCodeAssistant.run(
        source: 'void main() {\n// TODO: review\ntry {} catch (e) {}\n${'x' * 125}\n}',
        language: 'Dart',
        task: LocalAssistantTask.improve,
      );
      expect(report.items.join(' '), contains('TODO'));
      expect(report.items.join(' '), contains('catch'));
      expect(report.items.join(' '), contains('الأسطر الطويلة'));
    });

    test('detects possible credentials without echoing their values', () {
      final report = LocalCodeAssistant.run(
        source: 'const apiKey = "super-secret-value";',
        language: 'Dart',
        task: LocalAssistantTask.security,
      );
      expect(report.items.join(' '), contains('تخزينًا آمنًا'));
      expect(report.items.join(' '), isNot(contains('super-secret-value')));
    });

    test('finds duplicate imports', () {
      final report = LocalCodeAssistant.run(
        source: "import 'dart:io';\nimport 'dart:io';",
        language: 'Dart',
        task: LocalAssistantTask.improve,
      );
      expect(report.items.join(' '), contains('استيرادًا مكررًا'));
    });
  });
}
