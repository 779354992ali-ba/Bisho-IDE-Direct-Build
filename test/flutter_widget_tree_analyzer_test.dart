import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/flutter_widget_tree_analyzer.dart';

void main() {
  group('FlutterWidgetTreeAnalyzer', () {
    test('builds parent and child widget relationships', () {
      final nodes = FlutterWidgetTreeAnalyzer.analyze('''
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text('Hello')),
    body: Center(child: Column(children: [Text('A'), Icon(Icons.home)])),
  );
}
''');
      expect(nodes.map((node) => node.name), containsAllInOrder([
        'Scaffold', 'AppBar', 'Text', 'Center', 'Column', 'Text', 'Icon',
      ]));
      expect(nodes.first.name, 'Scaffold');
      expect(nodes[1].parentIndex, 0);
      expect(nodes[2].parentIndex, 1);
      expect(nodes[4].depth, 2);
    });

    test('ignores widget-like names in comments and strings', () {
      final nodes = FlutterWidgetTreeAnalyzer.analyze('''
// Scaffold(child: Text('comment'))
final sample = "Container(child: Icon())";
Widget build(BuildContext context) => Center(child: Text('real'));
''');
      expect(nodes.map((node) => node.name), ['Center', 'Text']);
    });

    test('preserves source line numbers and offsets', () {
      final nodes = FlutterWidgetTreeAnalyzer.analyze('''
Widget build(BuildContext context) {
  return Padding(
    child: Text('Hi'),
  );
}
''');
      expect(nodes.first.line, 2);
      expect(nodes.last.line, 3);
      expect(nodes.last.offset, greaterThan(nodes.first.offset));
    });

    test('honors node limit and empty input', () {
      expect(FlutterWidgetTreeAnalyzer.analyze('',), isEmpty);
      expect(FlutterWidgetTreeAnalyzer.analyze(
        'Row(children: [Text("a"), Icon(Icons.add)])',
        maximumNodes: 2,
      ), hasLength(2));
    });
  });
}
