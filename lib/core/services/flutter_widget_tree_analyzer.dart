/// Lightweight source-based Flutter widget tree inspection.
/// This does not connect to a running app or claim runtime layout information.
class FlutterWidgetNode {
  const FlutterWidgetNode({
    required this.name,
    required this.line,
    required this.offset,
    required this.depth,
    required this.parentIndex,
  });

  final String name;
  final int line;
  final int offset;
  final int depth;
  final int? parentIndex;
}

class FlutterWidgetTreeAnalyzer {
  const FlutterWidgetTreeAnalyzer._();

  static const Set<String> _widgets = {
    'MaterialApp', 'CupertinoApp', 'WidgetsApp', 'Scaffold', 'AppBar',
    'SafeArea', 'Center', 'Container', 'SizedBox', 'Padding', 'Row',
    'Column', 'Stack', 'ListView', 'GridView', 'Expanded', 'Flexible',
    'Positioned', 'Align', 'Text', 'RichText', 'Icon', 'Image',
    'CircleAvatar', 'Card', 'ListTile', 'ElevatedButton', 'TextButton',
    'OutlinedButton', 'IconButton', 'FloatingActionButton', 'TextField',
    'TextFormField', 'Form', 'DropdownButton', 'Switch', 'Checkbox',
    'Slider', 'TabBar', 'TabBarView', 'Drawer', 'NavigationBar',
    'BottomNavigationBar', 'SingleChildScrollView', 'Wrap', 'Spacer',
    'Divider', 'LinearProgressIndicator', 'CircularProgressIndicator',
    'Theme', 'Builder', 'GestureDetector', 'InkWell', 'Tooltip',
    'PopupMenuButton', 'ExpansionTile', 'FutureBuilder', 'StreamBuilder',
    'ValueListenableBuilder', 'LayoutBuilder', 'AnimatedContainer',
    'AnimatedBuilder', 'Hero', 'ClipRRect', 'DecoratedBox', 'AspectRatio',
    'ConstrainedBox', 'FittedBox', 'Transform', 'Opacity', 'Visibility',
    'CustomScrollView', 'SliverList', 'SliverGrid', 'Material',
    'CupertinoButton', 'CupertinoTextField', 'SelectableText',
  };

  static List<FlutterWidgetNode> analyze(
    String source, {
    int maximumNodes = 250,
  }) {
    if (source.isEmpty || maximumNodes <= 0) return const [];
    final code = _maskCommentsAndStrings(source);
    final nodes = <FlutterWidgetNode>[];
    final stack = <({String opener, int? widgetIndex})>[];
    var line = 1;
    var i = 0;

    while (i < code.length && nodes.length < maximumNodes) {
      final ch = code[i];
      if (ch == '\n') {
        line++;
        i++;
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
        final start = i;
        i++;
        while (i < code.length && RegExp(r'[A-Za-z0-9_]').hasMatch(code[i])) {
          i++;
        }
        final name = code.substring(start, i);
        var next = i;
        while (next < code.length && code[next].trim().isEmpty) {
          if (code[next] == '\n') line++;
          next++;
        }
        if (_widgets.contains(name) && next < code.length && code[next] == '(') {
          int? parent;
          for (var j = stack.length - 1; j >= 0; j--) {
            if (stack[j].widgetIndex != null) {
              parent = stack[j].widgetIndex;
              break;
            }
          }
          final index = nodes.length;
          nodes.add(FlutterWidgetNode(
            name: name,
            line: source.substring(0, start).split('\n').length,
            offset: start,
            depth: parent == null ? 0 : nodes[parent].depth + 1,
            parentIndex: parent,
          ));
          stack.add((opener: '(', widgetIndex: index));
          i = next + 1;
        }
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        stack.add((opener: ch, widgetIndex: null));
      } else if (ch == ')' || ch == ']' || ch == '}') {
        final expected = ch == ')' ? '(' : ch == ']' ? '[' : '{';
        for (var j = stack.length - 1; j >= 0; j--) {
          if (stack[j].opener == expected) {
            stack.removeRange(j, stack.length);
            break;
          }
        }
      }
      i++;
    }
    return List.unmodifiable(nodes);
  }

  static String _maskCommentsAndStrings(String source) {
    final chars = source.split('');
    var quote = '';
    var triple = false;
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var i = 0; i < chars.length; i++) {
      final ch = source[i];
      final next = i + 1 < source.length ? source[i + 1] : '';
      final third = i + 2 < source.length ? source[i + 2] : '';
      if (lineComment) {
        if (ch == '\n') {
          lineComment = false;
        } else {
          chars[i] = ' ';
        }
        continue;
      }
      if (blockComment) {
        if (ch == '*' && next == '/') {
          chars[i] = chars[i + 1] = ' ';
          blockComment = false;
          i++;
        } else if (ch != '\n') {
          chars[i] = ' ';
        }
        continue;
      }
      if (quote.isNotEmpty) {
        if (ch != '\n') chars[i] = ' ';
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == r'\\') {
          escaped = true;
          continue;
        }
        if (triple) {
          if (ch == quote && next == quote && third == quote) {
            chars[i] = chars[i + 1] = chars[i + 2] = ' ';
            i += 2;
            quote = '';
            triple = false;
          }
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == '/' && next == '/') {
        lineComment = true;
        chars[i] = chars[i + 1] = ' ';
        i++;
        continue;
      }
      if (ch == '/' && next == '*') {
        blockComment = true;
        chars[i] = chars[i + 1] = ' ';
        i++;
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        quote = ch;
        triple = (ch == "'" || ch == '"') && next == ch && third == ch;
        chars[i] = ' ';
        if (triple) {
          chars[i + 1] = chars[i + 2] = ' ';
          i += 2;
        }
      }
    }
    return chars.join();
  }
}
