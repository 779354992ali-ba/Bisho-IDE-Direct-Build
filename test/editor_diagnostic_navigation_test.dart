import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_diagnostic_navigation.dart';

void main() {
  group('EditorDiagnosticNavigation', () {
    test('maps one-based line and column to a text offset', () {
      expect(
        EditorDiagnosticNavigation.offsetForLineColumn('first\nsecond', 2, 3),
        8,
      );
    });

    test('clamps columns to the end of a line', () {
      expect(
        EditorDiagnosticNavigation.offsetForLineColumn('abc\nxy', 2, 99),
        6,
      );
    });

    test('handles CRLF without placing the cursor after the carriage return', () {
      expect(
        EditorDiagnosticNavigation.offsetForLineColumn('one\r\ntwo', 2, 2),
        6,
      );
    });

    test('returns null for invalid or missing line and column', () {
      expect(EditorDiagnosticNavigation.offsetForLineColumn('abc', 0, 1), isNull);
      expect(EditorDiagnosticNavigation.offsetForLineColumn('abc', 1, 0), isNull);
      expect(EditorDiagnosticNavigation.offsetForLineColumn('abc', 2, 1), isNull);
    });

    test('supports the empty final line after a trailing newline', () {
      expect(EditorDiagnosticNavigation.offsetForLineColumn('abc\n', 2, 1), 4);
    });
  });
}
