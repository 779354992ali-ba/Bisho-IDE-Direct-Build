import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/editor_minimap_model.dart';

void main() {
  group('EditorMinimapModel', () {
    test('maps each source line to its starting offset', () {
      final lines = EditorMinimapModel.fromText('first\nsecond\nthird');
      expect(lines.map((line) => line.number), [1, 2, 3]);
      expect(lines.map((line) => line.text), ['first', 'second', 'third']);
      expect(lines.map((line) => line.startOffset), [0, 6, 13]);
    });

    test('handles empty lines and Windows line endings', () {
      final lines = EditorMinimapModel.fromText('one\r\n\r\nthree');
      expect(lines.map((line) => line.text), ['one', '', 'three']);
      expect(lines.map((line) => line.startOffset), [0, 5, 7]);
    });

    test('bounds the model and handles empty source', () {
      expect(EditorMinimapModel.fromText(''), isEmpty);
      expect(EditorMinimapModel.fromText('a\nb\nc', maximumLines: 2), hasLength(2));
      expect(EditorMinimapModel.fromText('a', maximumLines: 0), isEmpty);
    });
  });
}
