
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import 'package:highlight/languages/dart.dart' as dart_lang;
import 'package:highlight/languages/python.dart' as python_lang;
import 'package:highlight/languages/javascript.dart' as js_lang;
import 'package:highlight/languages/typescript.dart' as ts_lang;
import 'package:highlight/languages/java.dart' as java_lang;
import 'package:highlight/languages/kotlin.dart' as kotlin_lang;
import 'package:highlight/languages/swift.dart' as swift_lang;
import 'package:highlight/languages/cpp.dart' as cpp_lang;
import 'package:highlight/languages/css.dart' as css_lang;
import 'package:highlight/languages/xml.dart' as xml_lang;
import 'package:highlight/languages/json.dart' as json_lang;
import 'package:highlight/languages/sql.dart' as sql_lang;
import 'package:highlight/languages/bash.dart' as bash_lang;
import 'package:highlight/languages/go.dart' as go_lang;
import 'package:highlight/languages/rust.dart' as rust_lang;
import 'package:highlight/languages/php.dart' as php_lang;
import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:highlight/languages/markdown.dart' as markdown_lang;
import 'package:highlight/languages/cs.dart' as cs_lang;
import 'package:highlight/languages/ruby.dart' as ruby_lang;
import 'package:highlight/languages/powershell.dart' as powershell_lang;
import 'package:highlight/languages/lua.dart' as lua_lang;
import 'package:highlight/languages/r.dart' as r_lang;
import 'package:highlight/languages/graphql.dart' as graphql_lang;
import 'package:highlight/languages/dockerfile.dart' as dockerfile_lang;
import 'package:highlight/languages/makefile.dart' as makefile_lang;
import 'package:highlight/languages/objectivec.dart' as objectivec_lang;
import 'package:highlight/languages/scala.dart' as scala_lang;
import 'package:highlight/languages/groovy.dart' as groovy_lang;
import 'package:highlight/languages/perl.dart' as perl_lang;
import 'package:highlight/languages/haskell.dart' as haskell_lang;
import 'package:highlight/languages/elixir.dart' as elixir_lang;
import 'package:highlight/languages/erlang.dart' as erlang_lang;
import 'package:highlight/languages/julia.dart' as julia_lang;
import 'package:highlight/languages/clojure.dart' as clojure_lang;
import 'package:highlight/languages/ini.dart' as ini_lang;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saf/saf.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import 'core/theme/bisho_theme.dart';
import 'core/services/saf_file_service.dart';
import 'core/languages/language_identity.dart';
import 'core/services/project_archive_validator.dart';
import 'features/projects/new_project_wizard.dart';
import 'flutter_preview_screen.dart';
import 'html_preview_screen.dart';
import 'web_code_runner_screen.dart';
import 'core/services/language_engine_manager.dart';
import 'core/services/editor_editing_assist.dart';
import 'core/services/editor_line_actions.dart';
import 'core/services/editor_text_navigation.dart';
import 'core/services/editor_syntax_diagnostics.dart';
import 'core/services/editor_diagnostic_navigation.dart';
import 'core/services/editor_extension_manifest.dart';
import 'core/services/editor_bracket_matcher.dart';
import 'core/services/editor_completion_engine.dart';
import 'core/services/editor_command_palette.dart';
import 'core/services/editor_symbol_insert.dart';
import 'core/services/workspace_metrics.dart';
import 'core/services/project_insights_analyzer.dart';
import 'core/services/project_backup_service.dart';
import 'core/services/project_backup_repository.dart';
import 'core/services/project_text_diff.dart';
import 'core/services/project_text_replacement.dart';
import 'core/services/github_repository_service.dart';
import 'core/services/flutter_widget_tree_analyzer.dart';
import 'core/services/flutter_package_catalog_service.dart';
import 'core/services/local_code_assistant.dart';
import 'core/services/editor_minimap_model.dart';
import 'features/terminal/bisho_terminal_panel.dart';
import 'features/tools/ide_tool_sheets.dart';
import 'core/services/file_version_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BishoThemeController.load();
  runApp(const BishoIDE());
}

class BishoIDE extends StatelessWidget {
  const BishoIDE({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: BishoThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Bisho IDE',
        debugShowCheckedModeBanner: false,
        theme: BishoTheme.lightTheme,
        darkTheme: BishoTheme.darkTheme,
        themeMode: mode,
        home: Theme(
          data: BishoTheme.darkTheme,
          child: const _BishoSplashGate(),
        ),
      ),
    );
  }
}

/// Page route that keeps the code workspace (previews, runners, fullscreen
/// editor) on the dark theme, which those screens are hand-styled for.
class _DarkPageRoute<T> extends MaterialPageRoute<T> {
  _DarkPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  Widget buildContent(BuildContext context) =>
      Theme(data: BishoTheme.darkTheme, child: super.buildContent(context));
}


/// Computes the 1-based line and column for [offset] without allocating a
/// substring or running a regex over the text on every rebuild.
(int, int) _cursorLineColumn(String text, int offset) {
  final end = offset.clamp(0, text.length).toInt();
  var line = 1;
  var lastBreak = -1;
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
      lastBreak = i;
    }
  }
  return (line, end - lastBreak);
}

PopupMenuItem<String> _bishoMenuItem(
  String value,
  IconData icon,
  String label, {
  Color color = const Color(0xFF38BDF8),
}) {
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

class _BishoSplashGate extends StatefulWidget {
  const _BishoSplashGate();

  @override
  State<_BishoSplashGate> createState() => _BishoSplashGateState();
}

class _BishoSplashGateState extends State<_BishoSplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    Future<void>.delayed(const Duration(milliseconds: 1450), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 850),
          pageBuilder: (_, __, ___) => const EditorScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: const Color(0xFF172337),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFF33465F)),
                  ),
                  child: const Icon(Icons.code_rounded,
                    size: 62, color: Color(0xFF38BDF8)),
                ),
                const SizedBox(height: 22),
                const Text('Bisho IDE', style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700,
                  letterSpacing: .2, color: Color(0xFFE5EDF7))),
                const SizedBox(height: 7),
                const Text('CODE  •  BUILD  •  CREATE', style: TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 2)),
                const SizedBox(height: 28),
                SizedBox(width: 150, child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Color(0xFF243247),
                    valueColor: AlwaysStoppedAnimation(Color(0xFF38BDF8)),
                  ),
                )),
                const SizedBox(height: 14),
                const Text('جاري تجهيز بيئة التطوير...', style: TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _PaletteCommand {
  const _PaletteCommand({
    required this.title,
    required this.description,
    required this.icon,
    required this.run,
    this.keywords = '',
  });

  final String title;
  final String description;
  final IconData icon;
  final FutureOr<void> Function() run;
  final String keywords;

  String get searchableText => '$title $description $keywords';
}

class EditorTab {
  final String id;
  final CodeController controller;

  String fileName;
  String language;

  String? fileUri;
  String? parentUri;

  bool isSaved;
  int selectionBaseOffset;
  int selectionExtentOffset;

  EditorTab({
    required this.id,
    required this.controller,
    required this.fileName,
    required this.language,
    this.fileUri,
    this.parentUri,
    this.isSaved = true,
    this.selectionBaseOffset = 0,
    this.selectionExtentOffset = 0,
  });
}

/// يمثل عنصرًا داخل شجرة SAF.
class _SafTreeEntry {
  final String uri;
  final String name;
  final String relativePath;
  final String? parentUri;
  final bool isDir;

  const _SafTreeEntry({
    required this.uri,
    required this.name,
    required this.relativePath,
    required this.parentUri,
    required this.isDir,
  });
}

class _ProjectSearchResult {
  final SafDocumentFile file;
  final String parentUri;
  final String relativePath;
  final List<int> matchingLines;

  const _ProjectSearchResult({
    required this.file,
    required this.parentUri,
    required this.relativePath,
    required this.matchingLines,
  });
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  static const String _savedDirectoryUriKey =
      'bisho_selected_directory_uri';

  static const String _savedDirectoryNameKey =
      'bisho_selected_directory_name';

  final Saf saf = Saf();
  final SafFileService safFiles = SafFileService();
  final GitHubRepositoryService _githubService = GitHubRepositoryService();
  final FlutterPackageCatalogService _packageCatalog = FlutterPackageCatalogService();

  final Map<String, dynamic> languages = {
    'Dart': dart_lang.dart,
    'Python': python_lang.python,
    'JavaScript': js_lang.javascript,
    'TypeScript': ts_lang.typescript,
    'Java': java_lang.java,
    'Kotlin': kotlin_lang.kotlin,
    'Swift': swift_lang.swift,
    'C': cpp_lang.cpp,
    'C++': cpp_lang.cpp,
    'CSS': css_lang.css,
    'HTML': xml_lang.xml,
    'XML': xml_lang.xml,
    'JSON': json_lang.json,
    'SQL': sql_lang.sql,
    'Bash': bash_lang.bash,
    'Go': go_lang.go,
    'Rust': rust_lang.rust,
    'PHP': php_lang.php,
    'Markdown': markdown_lang.markdown,
    'YAML': yaml_lang.yaml,
    'C#': cs_lang.cs,
    'Ruby': ruby_lang.ruby,
    'PowerShell': powershell_lang.powershell,
    'Lua': lua_lang.lua,
    'R': r_lang.r,
    'GraphQL': graphql_lang.graphql,
    'Dockerfile': dockerfile_lang.dockerfile,
    'Makefile': makefile_lang.makefile,
    'Objective-C': objectivec_lang.objectivec,
    'Scala': scala_lang.scala,
    'Groovy': groovy_lang.groovy,
    'Perl': perl_lang.perl,
    'Haskell': haskell_lang.haskell,
    'Elixir': elixir_lang.elixir,
    'Erlang': erlang_lang.erlang,
    'Julia': julia_lang.julia,
    'Clojure': clojure_lang.clojure,
    'TOML': ini_lang.ini,
    'SVG': xml_lang.xml,
  };

  final Map<String, String> extensions = {
    'Dart': 'dart',
    'Python': 'py',
    'JavaScript': 'js',
    'TypeScript': 'ts',
    'Java': 'java',
    'Kotlin': 'kt',
    'Swift': 'swift',
    'C': 'c',
    'C++': 'cpp',
    'CSS': 'css',
    'HTML': 'html',
    'XML': 'xml',
    'JSON': 'json',
    'SQL': 'sql',
    'Bash': 'sh',
    'Go': 'go',
    'Rust': 'rs',
    'PHP': 'php',
    'Markdown': 'md',
    'YAML': 'yaml',
    'C#': 'cs',
    'Ruby': 'rb',
    'PowerShell': 'ps1',
    'Lua': 'lua',
    'R': 'r',
    'GraphQL': 'graphql',
    'Dockerfile': 'Dockerfile',
    'Makefile': 'Makefile',
    'Objective-C': 'm',
    'Scala': 'scala',
    'Groovy': 'groovy',
    'Perl': 'pl',
    'Haskell': 'hs',
    'Elixir': 'ex',
    'Erlang': 'erl',
    'Julia': 'jl',
    'Clojure': 'clj',
    'TOML': 'toml',
    'SVG': 'svg',
    'Assembly': 'asm',
  };

  final List<EditorTab> tabs = [];

  int activeIndex = 0;
  int nextTabId = 1;
  int _explorerRevision = 0;
  String _explorerFilter = '';
  String _explorerTypeFilter = 'all';
  final TextEditingController _explorerFilterController = TextEditingController();

  String status = 'جاهز';

  String? projectUri;
  String projectName = 'لا يوجد مشروع';

  String? selectedDirectoryUri;
  String selectedDirectoryName = '';

  bool isRestoring = false;
  bool explorerVisible = true;
  bool _editorFullScreen = false;
  String? _splitTabId;
  bool _terminalFullScreen = false;
  bool _bottomPanelVisible = false;
  int _bottomPanelTab = 0;
  double _editorFontSize = 14;
  double _bottomPanelHeight = 154;
  final Map<String, List<String>> _undoHistory = {};
  final Map<String, List<String>> _redoHistory = {};
  final Set<String> _historyApplying = {};
  final Set<String> _autoPairApplying = {};
  Timer? _tabStateSaveTimer;
  bool _tabStateSaveInProgress = false;
  bool _tabStateSavePending = false;
  Completer<void>? _tabStateSaveCompleter;
  bool _isDisposing = false;

  static const String _fontSizePreferenceKey = 'bisho_editor_font_size';
  static const String _explorerVisiblePreferenceKey = 'bisho_explorer_visible';
  static const String _bottomPanelVisiblePreferenceKey = 'bisho_bottom_panel_visible';
  static const String _bottomPanelHeightPreferenceKey = 'bisho_bottom_panel_height';

  EditorTab get activeTab => tabs[activeIndex];

  String? get creationDirectoryUri {
    return selectedDirectoryUri ?? projectUri;
  }

  String get creationDirectoryName {
    if (selectedDirectoryUri == null) {
      return projectName;
    }

    return selectedDirectoryName;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreTabs();
  }

  String createId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${nextTabId++}';
  }

  EditorTab createTab({
    String fileName = 'untitled.dart',
    String language = 'Dart',
    String? code,
    String? fileUri,
    String? parentUri,
    bool isSaved = false,
    int selectionBaseOffset = 0,
    int selectionExtentOffset = 0,
  }) {
    final controller = CodeController(
      text: code ??
          '// Welcome to Bisho IDE\n\nvoid main() {\n  print("Hello World");\n}',
      language: languages[language] ?? languages['Dart'],
    );
    final safeBaseOffset = selectionBaseOffset
        .clamp(0, controller.text.length)
        .toInt();
    final safeExtentOffset = selectionExtentOffset
        .clamp(0, controller.text.length)
        .toInt();
    controller.selection = TextSelection(
      baseOffset: safeBaseOffset,
      extentOffset: safeExtentOffset,
    );

    final tab = EditorTab(
      id: createId(),
      controller: controller,
      fileName: fileName,
      language: language,
      fileUri: fileUri,
      parentUri: parentUri,
      isSaved: isSaved,
      selectionBaseOffset: safeBaseOffset,
      selectionExtentOffset: safeExtentOffset,
    );

    _undoHistory[tab.id] = <String>[controller.text];
    _redoHistory[tab.id] = <String>[];

    controller.addListener(() {
      if (_historyApplying.contains(tab.id)) return;

      // Auto-close a single newly typed opening delimiter. Multi-character
      // edits, paste operations, undo and redo are left untouched.
      if (!_autoPairApplying.contains(tab.id)) {
        final historyBeforeEdit =
            _undoHistory.putIfAbsent(tab.id, () => <String>[]);
        final previousText = historyBeforeEdit.isEmpty
            ? controller.text
            : historyBeforeEdit.last;
        _tryDeletePairedOpeningDelimiter(tab, previousText);
        _trySkipExistingClosingDelimiter(tab, previousText);
        _tryInsertClosingPair(tab, previousText);
        _tryAlignClosingDelimiter(tab, previousText);
        _tryAutoIndentNewline(tab, previousText);
      }

      final history = _undoHistory.putIfAbsent(tab.id, () => <String>[]);
      final textChanged = history.isEmpty || history.last != controller.text;
      final selection = controller.selection;
      final safeBaseOffset = selection.isValid
          ? selection.baseOffset.clamp(0, controller.text.length).toInt()
          : controller.text.length;
      final safeExtentOffset = selection.isValid
          ? selection.extentOffset.clamp(0, controller.text.length).toInt()
          : controller.text.length;
      final selectionChanged =
          tab.selectionBaseOffset != safeBaseOffset ||
          tab.selectionExtentOffset != safeExtentOffset;
      tab.selectionBaseOffset = safeBaseOffset;
      tab.selectionExtentOffset = safeExtentOffset;

      if (textChanged) {
        history.add(controller.text);
        // Bound undo memory by entry count and total characters so large
        // files do not keep ~100 full copies of themselves alive.
        var historyChars = 0;
        for (final entry in history) {
          historyChars += entry.length;
        }
        while (history.length > 101 ||
            (history.length > 2 && historyChars > 4000000)) {
          historyChars -= history.removeAt(0).length;
        }
        _redoHistory.putIfAbsent(tab.id, () => <String>[]).clear();
      }
      if (!mounted || isRestoring) return;

      // Selection changes also notify the controller. Refresh the cursor
      // indicator without incorrectly marking an unchanged file as dirty.
      setState(() {
        if (textChanged) {
          tab.isSaved = false;
          status = 'تعديلات جديدة';
        }
      });
      if (textChanged || selectionChanged) _scheduleTabStateSave();
    });

    return tab;
  }

  void _trySkipExistingClosingDelimiter(
    EditorTab tab,
    String previousText,
  ) {
    final controller = tab.controller;
    final result = EditorEditingAssist.skipExistingClosingDelimiter(
      previousText: previousText,
      currentText: controller.text,
      cursorOffset: controller.selection.extentOffset,
    );
    if (result == null) return;

    _autoPairApplying.add(tab.id);
    try {
      controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.cursorOffset),
      );
    } finally {
      _autoPairApplying.remove(tab.id);
    }
  }

  void _tryDeletePairedOpeningDelimiter(
    EditorTab tab,
    String previousText,
  ) {
    final controller = tab.controller;
    final result = EditorEditingAssist.deletePairedOpeningDelimiter(
      previousText: previousText,
      currentText: controller.text,
      cursorOffset: controller.selection.extentOffset,
    );
    if (result == null) return;

    _autoPairApplying.add(tab.id);
    try {
      controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.cursorOffset),
      );
    } finally {
      _autoPairApplying.remove(tab.id);
    }
  }

  void _tryAutoIndentNewline(EditorTab tab, String previousText) {
    final controller = tab.controller;
    final result = EditorEditingAssist.autoIndentNewline(
      previousText: previousText,
      currentText: controller.text,
      cursorOffset: controller.selection.extentOffset,
    );
    if (result == null) return;

    _autoPairApplying.add(tab.id);
    try {
      controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.cursorOffset),
      );
    } finally {
      _autoPairApplying.remove(tab.id);
    }
  }

  void _tryAlignClosingDelimiter(EditorTab tab, String previousText) {
    final controller = tab.controller;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final result = EditorEditingAssist.alignClosingDelimiter(
      previousText: previousText,
      currentText: controller.text,
      cursorOffset: selection.extentOffset,
      language: tab.language,
    );
    if (result == null) return;

    _autoPairApplying.add(tab.id);
    try {
      controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.cursorOffset),
      );
    } finally {
      _autoPairApplying.remove(tab.id);
    }
  }

  void _tryInsertClosingPair(EditorTab tab, String previousText) {
    final controller = tab.controller;
    final currentText = controller.text;
    if (currentText.length != previousText.length + 1) return;

    final cursor = controller.selection.extentOffset;
    if (cursor <= 0 || cursor > currentText.length) return;

    final insertionOffset = cursor - 1;
    if (currentText.substring(0, insertionOffset) !=
            previousText.substring(0, insertionOffset) ||
        currentText.substring(cursor) !=
            previousText.substring(insertionOffset)) {
      return;
    }

    final opening = currentText[insertionOffset];
    const closingPairs = <String, String>{
      '(': ')',
      '[': ']',
      '{': '}',
      '\'': '\'',
      '"': '"',
      '`': '`',
    };
    final closing = closingPairs[opening];
    if (closing == null) return;

    // Do not auto-pair an escaped quote.
    if (opening == '\'' || opening == '"' || opening == '`') {
      var backslashes = 0;
      for (var i = insertionOffset - 1; i >= 0 && currentText[i] == '\\'; i--) {
        backslashes++;
      }
      if (backslashes.isOdd) return;
    }

    final updatedText = currentText.replaceRange(
      cursor,
      cursor,
      closing,
    );
    _autoPairApplying.add(tab.id);
    try {
      controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection.collapsed(offset: cursor),
      );
    } finally {
      _autoPairApplying.remove(tab.id);
    }
  }

  Future<void> _saveEditorPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontSizePreferenceKey, _editorFontSize);
      await prefs.setBool(_explorerVisiblePreferenceKey, explorerVisible);
      await prefs.setBool(
        _bottomPanelVisiblePreferenceKey,
        _bottomPanelVisible,
      );
      await prefs.setDouble(
        _bottomPanelHeightPreferenceKey,
        _bottomPanelHeight,
      );
    } catch (_) {
      // Preferences are optional; editor actions must keep working if storage fails.
    }
  }

  Future<void> _saveSelectedDirectoryState() async {
    final prefs = await SharedPreferences.getInstance();

    if (selectedDirectoryUri == null ||
        selectedDirectoryUri!.isEmpty) {
      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);
      return;
    }

    await prefs.setString(
      _savedDirectoryUriKey,
      selectedDirectoryUri!,
    );

    await prefs.setString(
      _savedDirectoryNameKey,
      selectedDirectoryName,
    );
  }

  Future<void> _clearSavedDirectoryState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_savedDirectoryUriKey);
    await prefs.remove(_savedDirectoryNameKey);
  }

  Future<void> selectCreationDirectory(
    String directoryUri,
    String directoryName,
  ) async {
    if (projectUri == null) return;

    try {
      final directory = await safFiles.getItem(directoryUri);

      if (directory == null || !directory.isDir) {
        showMessage('هذا المجلد غير متاح');
        return;
      }

      final root = await safFiles.getItem(projectUri!);

      if (root == null || !root.isDir) {
        showMessage('تعذر الوصول إلى جذر المشروع');
        return;
      }

      final tree = await collectSubtree(root);

      final isInsideProject = tree.any(
        (entry) =>
            entry.uri == directoryUri &&
            entry.isDir,
      );

      if (!isInsideProject) {
        showMessage('المجلد ليس داخل المشروع المفتوح');
        return;
      }

      if (!mounted) return;

      setState(() {
        selectedDirectoryUri = directory.uri;
        selectedDirectoryName = directory.name.isNotEmpty
            ? directory.name
            : directoryName;
        status = 'مجلد العمل: $selectedDirectoryName';
      });

      await _saveSelectedDirectoryState();

      if (!mounted) return;

      showMessage(
        'تم حفظ "$selectedDirectoryName" كمجلد عمل',
      );
    } catch (e) {
      showMessage('تعذر تحديد مجلد العمل: $e');
    }
  }

  Future<void> resetCreationDirectory() async {
    if (projectUri == null) return;

    try {
      if (!mounted) return;

      setState(() {
        selectedDirectoryUri = null;
        selectedDirectoryName = '';
        status = 'مجلد العمل: جذر المشروع';
      });

      await _clearSavedDirectoryState();

      if (!mounted) return;

      showMessage('تمت العودة إلى جذر المشروع');
    } catch (e) {
      showMessage('تعذر تغيير مجلد العمل: $e');
    }
  }

  void refreshExplorer() {
    if (!mounted) return;

    setState(() {
      _explorerRevision++;
      status = 'تم تحديث المستكشف';
    });
  }

  Future<void> _restoreSelectedDirectory(
    SharedPreferences prefs,
  ) async {
    selectedDirectoryUri = null;
    selectedDirectoryName = '';

    try {
      if (projectUri == null || projectUri!.isEmpty) {
        await _clearSavedDirectoryState();
        return;
      }

      final savedUri = prefs.getString(_savedDirectoryUriKey);

      if (savedUri == null || savedUri.isEmpty) {
        return;
      }

      final root = await safFiles.getItem(projectUri!);

      if (root == null || !root.isDir) {
        await _clearSavedDirectoryState();
        return;
      }

      final tree = await collectSubtree(root);

      _SafTreeEntry? matchingDirectory;

      for (final entry in tree) {
        if (entry.uri == savedUri && entry.isDir) {
          matchingDirectory = entry;
          break;
        }
      }

      if (matchingDirectory == null) {
        await _clearSavedDirectoryState();
        return;
      }

      selectedDirectoryUri = matchingDirectory.uri;
      selectedDirectoryName = matchingDirectory.name;

      await _saveSelectedDirectoryState();
    } catch (_) {
      selectedDirectoryUri = null;
      selectedDirectoryName = '';

      try {
        await _clearSavedDirectoryState();
      } catch (_) {}
    }
  }

  Future<void> restoreTabs() async {
    isRestoring = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      _editorFontSize = (prefs.getDouble(_fontSizePreferenceKey) ?? 14.0)
          .clamp(10.0, 24.0)
          .toDouble();
      explorerVisible = prefs.getBool(_explorerVisiblePreferenceKey) ?? true;
      _bottomPanelVisible =
          prefs.getBool(_bottomPanelVisiblePreferenceKey) ?? false;
      _bottomPanelHeight = (prefs.getDouble(_bottomPanelHeightPreferenceKey) ?? 154.0)
          .clamp(110.0, 420.0)
          .toDouble();

      final savedTabs = prefs.getString('bisho_tabs');
      final savedIndex = prefs.getInt('bisho_active_index') ?? 0;

      final savedProjectUri =
          prefs.getString('bisho_project_uri');

      final savedProjectName =
          prefs.getString('bisho_project_name') ??
              'لا يوجد مشروع';

      projectUri = null;
      projectName = 'لا يوجد مشروع';

      selectedDirectoryUri = null;
      selectedDirectoryName = '';

      if (savedProjectUri != null &&
          savedProjectUri.isNotEmpty) {
        try {
          final permissions =
              await safFiles.getPersistedPermissions();

          final matchingPermission = permissions.where(
            (permission) =>
                permission.uri == savedProjectUri &&
                permission.read &&
                permission.write,
          );

          if (matchingPermission.isNotEmpty) {
            final root = await safFiles.getItem(savedProjectUri);

            if (root != null && root.isDir) {
              projectUri = savedProjectUri;
              projectName = savedProjectName;

              await _restoreSelectedDirectory(prefs);
            } else {
              await prefs.remove('bisho_project_uri');
              await prefs.remove('bisho_project_name');

              await _clearSavedDirectoryState();
            }
          } else {
            await prefs.remove('bisho_project_uri');
            await prefs.remove('bisho_project_name');

            await _clearSavedDirectoryState();
          }
        } catch (_) {
          projectUri = null;
          projectName = 'لا يوجد مشروع';

          selectedDirectoryUri = null;
          selectedDirectoryName = '';

          try {
            await prefs.remove('bisho_project_uri');
            await prefs.remove('bisho_project_name');

            await _clearSavedDirectoryState();
          } catch (_) {}
        }
      } else {
        await _clearSavedDirectoryState();
      }

      if (savedTabs != null) {
        final List<dynamic> data = jsonDecode(savedTabs);

        for (final item in data) {
          final language =
              item['language'] as String? ?? 'Dart';

          final safeLanguage =
              languages.containsKey(language)
                  ? language
                  : 'Dart';

          tabs.add(
            createTab(
              fileName:
                  item['fileName'] as String? ?? 'untitled.dart',
              language: safeLanguage,
              code: item['code'] as String? ?? '',
              fileUri: item['fileUri'] as String?,
              parentUri: item['parentUri'] as String?,
              isSaved: true,
              selectionBaseOffset: item['selectionBaseOffset'] is int
                  ? item['selectionBaseOffset'] as int
                  : ((item['cursorOffset'] is int)
                      ? item['cursorOffset'] as int
                      : 0),
              selectionExtentOffset: item['selectionExtentOffset'] is int
                  ? item['selectionExtentOffset'] as int
                  : ((item['cursorOffset'] is int)
                      ? item['cursorOffset'] as int
                      : 0),
            ),
          );
        }
      } else {
        final oldCode = prefs.getString('bisho_code');

        final oldName =
            prefs.getString('bisho_filename') ?? 'main.dart';

        final oldLanguage =
            prefs.getString('bisho_language') ?? 'Dart';

        final safeLanguage =
            languages.containsKey(oldLanguage)
                ? oldLanguage
                : 'Dart';

        tabs.add(
          createTab(
            fileName: oldName,
            language: safeLanguage,
            code: oldCode,
            isSaved: true,
          ),
        );
      }

      if (tabs.isEmpty) {
        tabs.add(createTab());
      }

      activeIndex =
          savedIndex.clamp(0, tabs.length - 1).toInt();
    } catch (e) {
      for (final tab in tabs) {
        tab.controller.dispose();
      }

      tabs.clear();
      tabs.add(createTab());

      activeIndex = 0;

      projectUri = null;
      projectName = 'لا يوجد مشروع';

      selectedDirectoryUri = null;
      selectedDirectoryName = '';
    }

    isRestoring = false;

    if (mounted) {
      setState(() {
        status = projectUri != null
            ? 'تم استعادة المشروع والملفات'
            : 'تم استعادة الملفات - افتح مجلد المشروع';
      });
    }
  }

  void _scheduleTabStateSave() {
    _tabStateSaveTimer?.cancel();
    _tabStateSaveTimer = Timer(const Duration(milliseconds: 650), () {
      saveTabStateSilently();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _tabStateSaveTimer?.cancel();
      saveTabStateSilently();
    }
  }

  Future<void> saveTabStateSilently() async {
    if (_tabStateSaveInProgress) {
      _tabStateSavePending = true;
      final inFlight = _tabStateSaveCompleter;
      if (inFlight != null) {
        await inFlight.future;
        if (!_isDisposing) await saveTabStateSilently();
      }
      return;
    }
    _tabStateSaveInProgress = true;
    _tabStateSaveCompleter = Completer<void>();
    // Snapshot synchronously so controller disposal cannot invalidate a pending save.
    final data = tabs.map((tab) {
      return {
        'fileName': tab.fileName,
        'language': tab.language,
        'code': tab.controller.text,
        'fileUri': tab.fileUri,
        'parentUri': tab.parentUri,
        'selectionBaseOffset': tab.selectionBaseOffset
            .clamp(0, tab.controller.text.length)
            .toInt(),
        'selectionExtentOffset': tab.selectionExtentOffset
            .clamp(0, tab.controller.text.length)
            .toInt(),
      };
    }).toList();
    final savedIndex = activeIndex;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bisho_tabs', jsonEncode(data));
      await prefs.setInt('bisho_active_index', savedIndex);
    } catch (_) {
      // Local recovery is best-effort and must never interrupt editing.
    } finally {
      _tabStateSaveInProgress = false;
      final completed = _tabStateSaveCompleter;
      _tabStateSaveCompleter = null;
      if (completed != null && !completed.isCompleted) {
        completed.complete();
      }
      if (_tabStateSavePending) {
        _tabStateSavePending = false;
        if (!_isDisposing) _scheduleTabStateSave();
      }
    }
  }

  String _mimeType(String name) {
    final ext =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';

    // Avoid Android SAF providers adding .txt to build/config files.
    if (const {'gradle', 'properties', 'bat', 'sh'}.contains(ext) ||
        name.toLowerCase() == 'gradlew') {
      return 'application/octet-stream';
    }

    const types = {
      'dart': 'text/plain',
      'py': 'text/x-python',
      'js': 'text/javascript',
      'ts': 'text/typescript',
      'html': 'text/html',
      'htm': 'text/html',
      'css': 'text/css',
      'json': 'application/json',
      'xml': 'application/xml',
      'java': 'text/x-java-source',
      'kt': 'text/plain',
      'php': 'text/plain',
      'sql': 'text/plain',
      'txt': 'text/plain',
    };

    return types[ext] ?? 'application/octet-stream';
  }

  FileVersionHistory? _fileVersionHistory;

  Future<FileVersionHistory?> _ensureVersionHistory() async {
    if (_fileVersionHistory != null) return _fileVersionHistory;
    try {
      final base = await getApplicationDocumentsDirectory();
      _fileVersionHistory = FileVersionHistory(
        Directory('${base.path}/bisho_file_versions'),
      );
    } catch (_) {
      return null;
    }
    return _fileVersionHistory;
  }

  String _versionKeyFor(EditorTab tab) =>
      '${tab.parentUri ?? 'standalone'}|${tab.fileName}';

  Future<void> _snapshotTabVersion(EditorTab tab, {String label = 'حفظ'}) async {
    try {
      final history = await _ensureVersionHistory();
      if (history == null) return;
      await history.snapshot(
        _versionKeyFor(tab),
        tab.fileName,
        tab.controller.text,
        label: label,
      );
    } catch (_) {
      // Version history is best-effort and must never block saving.
    }
  }

  Future<bool> saveTabToSAF(EditorTab tab) async {
    if (tab.parentUri == null || tab.parentUri!.isEmpty) {
      return false;
    }

    final bytes = Uint8List.fromList(
      utf8.encode(tab.controller.text),
    );

    final document = await safFiles.saveFile(
      parentUri: tab.parentUri!,
      fileName: tab.fileName,
      mimeType: _mimeType(tab.fileName),
      bytes: bytes,
      overwrite: true,
    );

    tab.fileUri = document.uri;
    tab.isSaved = true;
    await _snapshotTabVersion(tab);

    return true;
  }

  Future<void> saveAllTabs() async {
    try {
      int savedCount = 0;
      int skippedCount = 0;

      for (final tab in tabs) {
        if (tab.parentUri == null) {
          skippedCount++;
          continue;
        }

        await saveTabToSAF(tab);
        savedCount++;
      }

      await saveTabStateSilently();

      if (!mounted) return;

      setState(() {
        status = 'تم حفظ $savedCount ملف';
      });

      if (skippedCount > 0) {
        showMessage(
          'تم حفظ $savedCount ملف. '
          '$skippedCount ملف يحتاج إلى تصدير منفصل.',
        );
      } else {
        showMessage('تم حفظ جميع الملفات');
      }
    } catch (e) {
      showMessage('تعذر حفظ بعض الملفات: $e');
    }
  }

  Future<void> _confirmApplicationExit() async {
    if (!mounted) return;
    final unsavedCount = tabs.where((tab) => !tab.isSaved).length;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('الخروج من Bisho IDE؟'),
        content: Text(
          unsavedCount > 0
              ? 'لديك $unsavedCount ملف غير محفوظ. يمكنك حفظ الملفات المرتبطة بالمشروع، أو الخروج مع الاحتفاظ بنسخة الجلسة لاستعادتها عند فتح التطبيق مجددًا.'
              : 'سيتم حفظ جلسة العمل والتبويبات المفتوحة قبل إغلاق التطبيق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('إلغاء'),
          ),
          if (unsavedCount > 0)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'session'),
              child: const Text('الخروج مع حفظ الجلسة'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            icon: const Icon(Icons.save_rounded),
            label: Text(unsavedCount > 0 ? 'حفظ ثم خروج' : 'حفظ الجلسة والخروج'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'cancel' || !mounted) return;

    try {
      if (choice == 'save' && unsavedCount > 0) {
        await saveAllTabs();
      }
      await saveTabStateSilently();
    } catch (error) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعذر إكمال الحفظ'),
          content: Text('حدث خطأ أثناء حفظ الجلسة: $error\nهل تريد الخروج على أي حال؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('البقاء في التطبيق'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('الخروج'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) await SystemNavigator.pop();
  }

  void createNewTab() {
    setState(() {
      tabs.add(createTab());
      activeIndex = tabs.length - 1;
      status = 'تم إنشاء ملف جديد';
    });

    saveTabStateSilently();
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;

    setState(() {
      final previousId = activeTab.id;
      activeIndex = index;
      if (_splitTabId == tabs[index].id && previousId != tabs[index].id) {
        _splitTabId = previousId;
      }
      status = 'تم فتح ${activeTab.fileName}';
    });
    saveTabStateSilently();
  }

  Future<void> closeTab(int index) async {
    if (index < 0 || index >= tabs.length) return;

    final tab = tabs[index];

    if (!tab.isSaved) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('إغلاق الملف؟'),
          content: Text(
            'الملف ${tab.fileName} يحتوي على تعديلات غير محفوظة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إغلاق بدون حفظ'),
            ),
          ],
        ),
      );

      if (result != true || !mounted) return;
    }

    setState(() {
      tab.controller.dispose();
      tabs.removeAt(index);

      if (tabs.isEmpty) {
        tabs.add(createTab());
        activeIndex = 0;
      } else if (activeIndex > index) {
        activeIndex--;
      } else if (activeIndex >= tabs.length) {
        activeIndex = tabs.length - 1;
      }
    });

    await saveTabStateSilently();
  }

  String detectLanguage(String extension) =>
      LanguageIdentity.fromFileName('file.$extension').name;

  Future<void> openFile() async {
    try {
      final file = await saf.pickFile(
        persistablePermission: true,
      );

      if (file == null) return;

      final bytes = await safFiles.readFile(file.uri);
      if (!mounted) return;
      final content = utf8.decode(bytes, allowMalformed: true);

      final extension =
          file.name.contains('.') ? file.name.split('.').last : '';

      final language = detectLanguage(extension);

      final existingIndex = tabs.indexWhere(
        (tab) => tab.fileUri == file.uri,
      );

      if (existingIndex != -1) {
        selectTab(existingIndex);
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      setState(() {
        tabs.add(
          createTab(
            fileName: file.name,
            language: language,
            code: content,
            fileUri: file.uri,
            parentUri: null,
            isSaved: true,
          ),
        );

        activeIndex = tabs.length - 1;
        status = 'تم فتح الملف';
      });

      await _snapshotTabVersion(tabs.last, label: 'عند الفتح');
      await saveTabStateSilently();
    } catch (e) {
      showMessage('تعذر فتح الملف: $e');
    }
  }

  /// استيراد مشروع موجود من مساحة تخزين Android عبر SAF.
  ///
  /// لا ينسخ ملفات المستخدم ولا ينقلها؛ بل يمنح التطبيق صلاحية مستمرة
  /// للمجلد المختار ويعيّنه كجذر المشروع الحالي داخل مستكشف Bisho IDE.
  /// تبقى الملفات في مكانها الأصلي ويمكن تحريرها وحفظها مباشرة.
  Future<void> importExistingProject() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استيراد مشروع موجود'),
        content: const Text(
          'اختر مجلد المشروع من ذاكرة الجهاز. '
          'سيتم ربطه بمستكشف Bisho IDE مع الاحتفاظ بملفاته في مكانها الأصلي، '
          'ويمكنك فتح الملفات وتعديلها وحفظها مباشرة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('اختيار مجلد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await openProjectFolder();
    if (!mounted) return;
    if (projectUri != null && projectUri!.isNotEmpty) {
      try {
        final root = await safFiles.getItem(projectUri!);
        if (root == null || !root.isDir) {
          showMessage('تعذر التحقق من مجلد المشروع المستورد');
          return;
        }
        final children = await safFiles.listDirectory(projectUri!);
        showMessage(
          'تم استيراد "$projectName" بنجاح • ${children.length} عنصر في المجلد الرئيسي',
        );
      } catch (error) {
        showMessage('تم ربط المشروع، لكن تعذر قراءة محتوياته: $error');
      }
    }
  }

  static const String _recentProjectsKey = 'bisho_recent_projects_v1';
  static const String _favoriteProjectsKey = 'bisho_favorite_projects_v1';

  Future<List<Map<String, String>>> _readRecentProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentProjectsKey);
      if (raw == null || raw.isEmpty) return <Map<String, String>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, String>>[];
      return decoded.whereType<Map>().map((item) => <String, String>{
        'uri': item['uri']?.toString() ?? '',
        'name': item['name']?.toString() ?? 'مشروع',
        'openedAt': item['openedAt']?.toString() ?? '',
      }).where((item) => item['uri']!.isNotEmpty).toList();
    } catch (_) {
      return <Map<String, String>>[];
    }
  }

  Future<void> _rememberProject(String uri, String name) async {
    if (uri.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = await _readRecentProjects();
      final favorites = await _readFavoriteProjects();
      recent.removeWhere((item) => item['uri'] == uri);
      recent.insert(0, <String, String>{
        'uri': uri,
        'name': name.isEmpty ? 'مشروع' : name,
        'openedAt': DateTime.now().toIso8601String(),
      });
      while (recent.length > 12) {
        final removableIndex = recent.lastIndexWhere(
          (item) => !favorites.contains(item['uri']),
        );
        if (removableIndex < 0) break;
        recent.removeAt(removableIndex);
      }
      await prefs.setString(_recentProjectsKey, jsonEncode(recent));
    } catch (_) {
      // Project opening must remain available when optional history storage fails.
    }
  }

  Future<Set<String>> _readFavoriteProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_favoriteProjectsKey)?.toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _toggleFavoriteProject(String uri) async {
    if (uri.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = await _readFavoriteProjects();
      if (!favorites.add(uri)) {
        favorites.remove(uri);
      }
      await prefs.setStringList(_favoriteProjectsKey, favorites.toList());
    } catch (_) {
      showMessage('تعذر حفظ قائمة المشاريع المفضلة');
    }
  }

  Future<void> _openRememberedProject(String uri, String name) async {
    try {
      final permissions = await safFiles.getPersistedPermissions();
      final permission = permissions.where((item) =>
        item.uri == uri && item.read && item.write,
      );
      if (permission.isEmpty) {
        showMessage('انتهت صلاحية الوصول لهذا المشروع. أعد فتحه من اختيار المجلد.');
        return;
      }
      final directory = await safFiles.getItem(uri);
      if (directory == null || !directory.isDir) {
        showMessage('المشروع لم يعد متاحاً في موقعه الأصلي.');
        return;
      }
      if (projectUri != uri) {
        final projectTabs = tabs.where((tab) =>
          tab.parentUri != null && tab.parentUri!.isNotEmpty,
        ).toList();
        final unsavedCount = projectTabs.where((tab) => !tab.isSaved).length;
        if (projectUri != null && projectTabs.isNotEmpty) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('تبديل المشروع؟'),
              content: Text(
                unsavedCount > 0
                  ? 'يوجد $unsavedCount ملف غير محفوظ. ستبقى التبويبات القديمة مرتبطة بمجلداتها ولن تُحذف.'
                  : 'ستبقى التبويبات القديمة مفتوحة ومرتبطة بمجلداتها الأصلية.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('متابعة'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
        }
      }
      await saveTabStateSilently();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bisho_project_uri', uri);
      await prefs.setString('bisho_project_name', directory.name.isNotEmpty ? directory.name : name);
      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);
      if (!mounted) return;
      setState(() {
        projectUri = uri;
        projectName = directory.name.isNotEmpty ? directory.name : name;
        selectedDirectoryUri = null;
        selectedDirectoryName = '';
        explorerVisible = true;
        _explorerRevision++;
        status = 'تم فتح المشروع من المدير الذكي';
      });
      await _rememberProject(uri, projectName);
      showMessage('تم فتح $projectName');
    } catch (error) {
      showMessage('تعذر فتح المشروع المحفوظ: $error');
    }
  }

  Future<void> showProjectManager() async {
    var recent = await _readRecentProjects();
    var favorites = await _readFavoriteProjects();
    if (!mounted) return;
    final searchController = TextEditingController();
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final filtered = recent.where((item) {
            final name = item['name']!.toLowerCase();
            final uri = item['uri']!.toLowerCase();
            return normalized.isEmpty || name.contains(normalized) || uri.contains(normalized);
          }).toList();
          final favoriteItems = filtered.where((item) => favorites.contains(item['uri'])).toList();
          final otherItems = filtered.where((item) => !favorites.contains(item['uri'])).toList();

          Widget projectTile(Map<String, String> item) {
            final uri = item['uri']!;
            final name = item['name']!;
            final isCurrent = projectUri == uri;
            final isFavorite = favorites.contains(uri);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              leading: CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFF38BDF8).withValues(alpha: .12),
                child: Icon(isCurrent ? Icons.folder_open_rounded : Icons.folder_rounded,
                  color: const Color(0xFF38BDF8), size: 20),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text(
                isCurrent ? 'المشروع المفتوح حالياً' : 'آخر فتح: ${item['openedAt']!.isEmpty ? 'غير محدد' : item['openedAt']!.replaceFirst('T', ' ').split('.').first}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                    onPressed: () async {
                      await _toggleFavoriteProject(uri);
                      favorites = await _readFavoriteProjects();
                      if (context.mounted) setDialogState(() {});
                    },
                    icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFavorite ? const Color(0xFFFBBF24) : Colors.white54),
                  ),
                  IconButton(
                    tooltip: 'فتح المشروع',
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await _openRememberedProject(uri, name);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF34D399)),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            title: Row(
              children: [
                const Icon(Icons.workspaces_rounded, color: Color(0xFF38BDF8)),
                const SizedBox(width: 10),
                const Expanded(child: Text('مدير المشاريع الذكي')),
                IconButton(
                  tooltip: 'تحديث القائمة',
                  onPressed: () async {
                    recent = await _readRecentProjects();
                    favorites = await _readFavoriteProjects();
                    if (context.mounted) setDialogState(() {});
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(dialogContext).size.height * .62,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (value) => setDialogState(() => query = value),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن مشروع أو مساره...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty ? null : IconButton(
                        onPressed: () {
                          searchController.clear();
                          setDialogState(() => query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: recent.isEmpty
                      ? const Center(child: Text('ستظهر هنا المشاريع التي تفتحها لاحقاً.'))
                      : filtered.isEmpty
                        ? const Center(child: Text('لا توجد مشاريع مطابقة للبحث.'))
                        : ListView(
                            children: [
                              if (favoriteItems.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(4, 4, 4, 6),
                                  child: Text('المشاريع المفضلة', style: TextStyle(
                                    color: Color(0xFFFBBF24), fontWeight: FontWeight.w800)),
                                ),
                                ...favoriteItems.map(projectTile),
                              ],
                              if (otherItems.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
                                  child: Text('المشاريع الأخيرة', style: TextStyle(
                                    color: Color(0xFF38BDF8), fontWeight: FontWeight.w800)),
                                ),
                                ...otherItems.map(projectTile),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await openProjectFolder();
                },
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('فتح مجلد آخر'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
  }

  Future<void> openProjectFolder() async {
    try {
      final directory = await safFiles.pickProjectFolder();

      if (directory == null || !mounted) return;

      if (projectUri == directory.uri) {
        refreshExplorer();
        showMessage('هذا المشروع مفتوح بالفعل');
        return;
      }

      final projectTabs = tabs
          .where((tab) =>
              tab.parentUri != null && tab.parentUri!.isNotEmpty)
          .toList();

      final unsavedCount =
          projectTabs.where((tab) => !tab.isSaved).length;

      if (projectUri != null && projectTabs.isNotEmpty) {
        final message = unsavedCount > 0
            ? 'يوجد $unsavedCount ملف غير محفوظ في المشروع الحالي.\n\n'
                'ستبقى التبويبات القديمة مفتوحة ومرتبطة بمجلداتها الأصلية. '
                'لن يتم نقلها إلى المشروع الجديد.'
            : 'ستبقى تبويبات المشروع الحالي مفتوحة ومرتبطة بمجلداتها الأصلية. '
                'لن يتم نقلها إلى المشروع الجديد.';

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تغيير المشروع؟'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        );

        if (confirmed != true || !mounted) return;
      }

      await saveTabStateSilently();

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('bisho_project_uri', directory.uri);
      await prefs.setString('bisho_project_name', directory.name);

      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);

      if (!mounted) return;

      setState(() {
        projectUri = directory.uri;
        projectName = directory.name;

        selectedDirectoryUri = null;
        selectedDirectoryName = '';

        explorerVisible = true;
        _explorerRevision++;
        status = 'تم فتح المشروع عبر SAF';
      });

      await _rememberProject(directory.uri, directory.name);
      showMessage('تم فتح مجلد المشروع');
    } catch (e) {
      showMessage('تعذر فتح المجلد: $e');
    }
  }

  /// إنشاء مشروع جديد باستخدام معالج المشاريع وSAF.
  Future<void> createNewProject() async {
    bool firstDirectory = true;

    try {
      await NewProjectWizard.show(
        context,
        pickLocation: () async {
          final folder = await safFiles.pickProjectFolder();

          if (folder == null) return null;

          return ProjectSaveLocation(
            uri: folder.uri,
            name: folder.name,
          );
        },
        createDirectory: (parentUri, directoryName) async {
          final existing = await safFiles.findChild(
            parentUri: parentUri,
            name: directoryName,
          );

          if (firstDirectory) {
            firstDirectory = false;

            if (existing != null) {
              throw Exception(
                'يوجد عنصر بالاسم "$directoryName" '
                'في مجلد الحفظ. اختر اسمًا آخر أو مجلدًا مختلفًا.',
              );
            }
          } else {
            if (existing != null) {
              if (existing.isDir) {
                return existing.uri;
              }

              throw Exception(
                'يوجد ملف بالاسم "$directoryName" '
                'ولا يمكن استخدامه كمجلد.',
              );
            }
          }

          final folder = await safFiles.createFolder(
            parentUri: parentUri,
            folderName: directoryName,
          );

          return folder.uri;
        },
        writeFile: (
          parentUri,
          fileName,
          mimeType,
          bytes,
        ) async {
          await safFiles.saveFile(
            parentUri: parentUri,
            fileName: fileName,
            mimeType: mimeType,
            bytes: Uint8List.fromList(bytes),
            overwrite: false,
          );
        },
        deleteDirectoryTree: (rootUri) => safFiles.deleteTree(rootUri),
        onCreated: (project) async {
          final prefs = await SharedPreferences.getInstance();

          await prefs.setString(
            'bisho_project_uri',
            project.rootUri,
          );

          await prefs.setString(
            'bisho_project_name',
            project.name,
          );

          await prefs.remove(_savedDirectoryUriKey);
          await prefs.remove(_savedDirectoryNameKey);

          if (!mounted) return;

          setState(() {
            projectUri = project.rootUri;
            projectName = project.name;

            selectedDirectoryUri = null;
            selectedDirectoryName = '';

            explorerVisible = true;
            _explorerRevision++;

            status = 'تم إنشاء المشروع ${project.name}';
          });

          await _rememberProject(project.rootUri, project.name);

          // البحث عن ملف البداية داخل المشروع.
          try {
            final segments = project.entryFile
                .split('/')
                .where((segment) => segment.isNotEmpty)
                .toList();

            var currentUri = project.rootUri;
            SafDocumentFile? entryFile;
            var entryParentUri = currentUri;

            for (var i = 0; i < segments.length; i++) {
              final found = await safFiles.findChild(
                parentUri: currentUri,
                name: segments[i],
              );

              if (found == null) {
                break;
              }

              if (i == segments.length - 1) {
                if (!found.isDir) {
                  entryFile = found;
                  entryParentUri = currentUri;
                }
              } else {
                if (!found.isDir) {
                  break;
                }

                currentUri = found.uri;
              }
            }

            if (!mounted) return;

            if (entryFile != null) {
              // لا تغلق المسار الحالي هنا: معالج إنشاء المشروع
              // مسؤول عن إغلاق نافذته بعد اكتمال onCreated.
              await openProjectFile(
                entryFile,
                entryParentUri,
                closeOverlay: false,
              );
            } else {
              showMessage(
                'تم إنشاء المشروع، لكن تعذر العثور على ملف البداية.',
              );
            }
          } catch (e) {
            showMessage(
              'تم إنشاء المشروع، لكن تعذر فتح ملف البداية: $e',
            );
          }

          await saveTabStateSilently();

          if (!mounted) return;

          if (project.isFlutterSourceOnly) {
            showMessage(
              'تم إنشاء مشروع Flutter مع هيكل Android وملفات Gradle محليًا. '
              'يمكنك الآن ربط GitHub لإنشاء المستودع ورفع المشروع وبدء البناء تلقائيًا.',
            );
          } else {
            showMessage(
              'تم إنشاء المشروع وفتح ملف البداية بنجاح',
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      showMessage('تعذر إنشاء المشروع: $e');
    }
  }

  Future<void> openProjectFile(
    SafDocumentFile file,
    String parentUri, {
    bool closeOverlay = true,
  }) async {
    try {
      final bytes = await safFiles.readFile(file.uri);
      if (!mounted) return;
      final content = utf8.decode(bytes, allowMalformed: true);

      final extension =
          file.name.contains('.') ? file.name.split('.').last : '';

      final language = detectLanguage(extension);

      final existingIndex = tabs.indexWhere(
        (tab) => tab.fileUri == file.uri,
      );

      if (existingIndex != -1) {
        selectTab(existingIndex);
        if (closeOverlay && Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      setState(() {
        tabs.add(
          createTab(
            fileName: file.name,
            language: language,
            code: content,
            fileUri: file.uri,
            parentUri: parentUri,
            isSaved: true,
          ),
        );

        activeIndex = tabs.length - 1;
        status = 'تم فتح ${file.name}';
      });

      await _snapshotTabVersion(tabs.last, label: 'عند الفتح');
      await saveTabStateSilently();
      if (closeOverlay && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      showMessage('تعذر قراءة الملف: $e');
    }
  }

  Future<void> createProjectFile() async {
    final targetUri = creationDirectoryUri;

    if (targetUri == null || targetUri.isEmpty) {
      showMessage('افتح مجلد مشروع أولاً');
      return;
    }

    final targetName = creationDirectoryName;

    final name = await askName(
      'إنشاء ملف داخل $targetName',
      'مثال: main.dart',
    );

    if (name == null || name.trim().isEmpty || !mounted) return;

    final fileName = name.trim();

    if (fileName.contains('/') || fileName.contains('\\')) {
      showMessage('اكتب اسم ملف فقط');
      return;
    }

    try {
      final document = await safFiles.saveFile(
        parentUri: targetUri,
        fileName: fileName,
        mimeType: _mimeType(fileName),
        bytes: Uint8List(0),
        overwrite: false,
      );

      final language = detectLanguage(
        fileName.contains('.') ? fileName.split('.').last : '',
      );

      if (!mounted) return;

      setState(() {
        tabs.add(
          createTab(
            fileName: fileName,
            language: language,
            code: '',
            fileUri: document.uri,
            parentUri: targetUri,
            isSaved: true,
          ),
        );

        activeIndex = tabs.length - 1;
        _explorerRevision++;
        status = 'تم إنشاء الملف داخل $targetName';
      });

      await saveTabStateSilently();
      showMessage('تم إنشاء الملف داخل $targetName');
    } catch (e) {
      showMessage('تعذر إنشاء الملف: $e');
    }
  }

  Future<void> createProjectFolder() async {
    final targetUri = creationDirectoryUri;

    if (targetUri == null || targetUri.isEmpty) {
      showMessage('افتح مجلد مشروع أولاً');
      return;
    }

    final targetName = creationDirectoryName;

    final name = await askName(
      'إنشاء مجلد داخل $targetName',
      'اسم المجلد',
    );

    if (name == null || name.trim().isEmpty || !mounted) return;

    final folderName = name.trim();

    if (folderName.contains('/') || folderName.contains('\\')) {
      showMessage('اكتب اسم مجلد فقط');
      return;
    }

    try {
      await safFiles.createFolder(
        parentUri: targetUri,
        folderName: folderName,
      );

      if (!mounted) return;

      setState(() {
        _explorerRevision++;
        status = 'تم إنشاء المجلد داخل $targetName';
      });

      showMessage('تم إنشاء المجلد داخل $targetName');
    } catch (e) {
      showMessage('تعذر إنشاء المجلد: $e');
    }
  }

  Future<String?> askName(String title, String hint) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('موافق'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<List<_SafTreeEntry>> collectSubtree(
    SafDocumentFile root,
  ) async {
    final result = <_SafTreeEntry>[];
    final visited = <String>{};

    Future<void> visit(
      SafDocumentFile item, {
      required String relativePath,
      required String? parentUri,
      int depth = 0,
    }) async {
      if (depth > 64) {
        throw StateError('تجاوز عمق المشروع الحد المسموح أثناء فحص الملفات.');
      }
      if (!visited.add(item.uri)) return;

      result.add(
        _SafTreeEntry(
          uri: item.uri,
          name: item.name,
          relativePath: relativePath,
          parentUri: parentUri,
          isDir: item.isDir,
        ),
      );

      if (!item.isDir) return;

      final children = await safFiles.listDirectory(item.uri);

      for (final child in children) {
        final childPath = relativePath.isEmpty
            ? child.name
            : '$relativePath/${child.name}';

        await visit(
          child,
          relativePath: childPath,
          parentUri: item.uri,
          depth: depth + 1,
        );
      }
    }

    await visit(
      root,
      relativePath: '',
      parentUri: null,
    );

    return result;
  }

  Future<SafDocumentFile> _copySafTree(
    SafDocumentFile source,
    String targetParentUri, {
    String? targetName,
    int depth = 0,
  }) async {
    if (depth > 64) {
      throw StateError('تجاوز عمق المجلد الحد المسموح أثناء النسخ.');
    }
    if (source.isDir) {
      final destination = await safFiles.createFolder(
        parentUri: targetParentUri,
        folderName: targetName ?? source.name,
      );
      try {
        final children = await safFiles.listDirectory(source.uri);
        for (final child in children) {
          await _copySafTree(child, destination.uri, depth: depth + 1);
        }
        return destination;
      } catch (_) {
        try { await safFiles.deleteTree(destination.uri); } catch (_) { /* Preserve the original even if cleanup is unavailable. */ }
        rethrow;
      }
    }
    final openTabIndex = tabs.indexWhere((tab) => tab.fileUri == source.uri);
    final bytes = openTabIndex >= 0
        ? utf8.encode(tabs[openTabIndex].controller.text)
        : await safFiles.readFile(source.uri);
    return safFiles.saveFile(
      parentUri: targetParentUri,
      fileName: targetName ?? source.name,
      mimeType: SafFileService.mimeTypeForName(targetName ?? source.name),
      bytes: Uint8List.fromList(bytes),
      overwrite: false,
    );
  }

  Future<void> copyOrMoveEntity(
    SafDocumentFile entity, {required bool move}) async {
    SafDocumentFile? copiedRoot;
    var copyCompleted = false;
    try {
      final destination = await safFiles.pickProjectFolder();
      if (destination == null || !mounted) return;
      final oldTree = await collectSubtree(entity);
      if (oldTree.any((entry) => entry.uri == destination.uri)) {
        showMessage('لا يمكن نسخ أو نقل مجلد إلى نفسه أو إلى أحد مجلداته');
        return;
      }
      final collision = await safFiles.findChild(
        parentUri: destination.uri, name: entity.name);
      if (collision != null) {
        showMessage('يوجد عنصر باسم ${entity.name} في مجلد الوجهة؛ لم يتم استبداله');
        return;
      }
      final copied = await _copySafTree(entity, destination.uri);
      copiedRoot = copied;
      copyCompleted = true;
      if (!move) {
        if (!mounted) return;
        setState(() {
          _explorerRevision++;
          status = 'تم نسخ ${entity.name}';
        });
        showMessage('تم نسخ ${entity.name} إلى ${destination.name}');
        return;
      }

      // Copy completes and is enumerated before deleting the source.
      final newTree = entity.isDir
          ? await collectSubtree(copied)
          : <_SafTreeEntry>[
              _SafTreeEntry(uri: copied.uri, name: copied.name,
                relativePath: '', parentUri: destination.uri, isDir: false),
            ];
      await safFiles.deleteItem(entity.uri);
      final oldByUri = <String, _SafTreeEntry>{
        for (final item in oldTree) item.uri: item,
      };
      final newByPath = <String, _SafTreeEntry>{
        for (final item in newTree) item.relativePath: item,
      };
      for (final tab in tabs) {
        final oldFile = tab.fileUri == null ? null : oldByUri[tab.fileUri];
        if (oldFile != null) {
          final replacement = newByPath[oldFile.relativePath];
          if (replacement != null) {
            tab.fileUri = replacement.uri;
            tab.fileName = replacement.name;
          }
        }
        if (tab.parentUri != null && oldByUri.containsKey(tab.parentUri)) {
          final oldParent = oldByUri[tab.parentUri];
          final replacement = oldParent == null ? null : newByPath[oldParent.relativePath];
          if (replacement != null) tab.parentUri = replacement.uri;
        } else if (!entity.isDir && tab.fileUri == copied.uri) {
          tab.parentUri = destination.uri;
        }
      }
      if (selectedDirectoryUri != null && oldByUri.containsKey(selectedDirectoryUri)) {
        final oldSelected = oldByUri[selectedDirectoryUri];
        final replacement = oldSelected == null ? null : newByPath[oldSelected.relativePath];
        if (replacement != null) {
          selectedDirectoryUri = replacement.uri;
          selectedDirectoryName = replacement.name;
        }
      }
      if (!mounted) return;
      setState(() {
        _explorerRevision++;
        status = 'تم نقل ${entity.name}';
      });
      await _saveSelectedDirectoryState();
      await saveTabStateSilently();
      showMessage('تم نقل ${entity.name} بنجاح');
    } catch (error) {
      if (!copyCompleted && copiedRoot != null) {
        try { await safFiles.deleteTree(copiedRoot.uri); } catch (_) { /* Keep original; report cleanup failure below. */ }
      }
      refreshExplorer();
      showMessage('تعذرت عملية ${move ? 'النقل' : 'النسخ'}: $error');
    }
  }

  Future<void> renameEntity(SafDocumentFile entity) async {
    final name = await askName('إعادة تسمية', entity.name);

    if (name == null || name.trim().isEmpty || !mounted) return;

    final newName = name.trim();

    if (newName.contains('/') || newName.contains('\\')) {
      showMessage('اكتب اسمًا فقط');
      return;
    }

    if (newName == entity.name) return;

    try {
      final oldTree = await collectSubtree(entity);

      final renamed = await safFiles.renameItem(
        uri: entity.uri,
        newName: newName,
      );

      if (entity.isDir) {
        final newTree = await collectSubtree(renamed);

        final oldByUri = <String, _SafTreeEntry>{
          for (final item in oldTree) item.uri: item,
        };

        final newByPath = <String, _SafTreeEntry>{
          for (final item in newTree) item.relativePath: item,
        };

        if (selectedDirectoryUri != null) {
          final selectedEntry = oldByUri[selectedDirectoryUri];

          if (selectedEntry != null) {
            final newSelectedEntry =
                newByPath[selectedEntry.relativePath];

            if (newSelectedEntry != null) {
              selectedDirectoryUri = newSelectedEntry.uri;
              selectedDirectoryName = newSelectedEntry.name;
            }
          }
        }

        for (final tab in tabs) {
          final oldFileEntry = tab.fileUri == null
              ? null
              : oldByUri[tab.fileUri];

          if (oldFileEntry != null) {
            final newFileEntry =
                newByPath[oldFileEntry.relativePath];

            if (newFileEntry != null) {
              tab.fileUri = newFileEntry.uri;
              tab.fileName = newFileEntry.name;
            }
          }

          if (tab.parentUri != null) {
            final oldParentEntry = oldByUri[tab.parentUri];

            if (oldParentEntry != null) {
              final newParentEntry =
                  newByPath[oldParentEntry.relativePath];

              if (newParentEntry != null) {
                tab.parentUri = newParentEntry.uri;
              }
            }
          }
        }
      } else {
        for (final tab in tabs) {
          if (tab.fileUri == entity.uri) {
            tab.fileUri = renamed.uri;
            tab.fileName = renamed.name;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _explorerRevision++;
        status = 'تم تغيير الاسم';
      });

      await _saveSelectedDirectoryState();
      await saveTabStateSilently();

      if (!mounted) return;

      showMessage('تم تغيير الاسم وتحديث البيانات المحفوظة');
    } catch (e) {
      refreshExplorer();
      showMessage('تعذرت إعادة التسمية أو تحديث التبويبات: $e');
    }
  }

  Future<void> deleteEntity(SafDocumentFile entity) async {
    try {
      final subtree = await collectSubtree(entity);
      if (!mounted) return;

      final deletedUris = subtree.map((item) => item.uri).toSet();

      final affectedTabs = tabs.where((tab) {
        final fileIsInside = tab.fileUri != null &&
            deletedUris.contains(tab.fileUri);

        final parentIsInside = tab.parentUri != null &&
            deletedUris.contains(tab.parentUri);

        return fileIsInside || parentIsInside;
      }).toList();

      final unsavedCount =
          affectedTabs.where((tab) => !tab.isSaved).length;

      final message = unsavedCount > 0
          ? 'هل تريد حذف ${entity.name}؟\n\n'
              'يوجد $unsavedCount ملف مفتوح يحتوي على تعديلات غير محفوظة. '
              'سيتم إغلاق التبويبات التابعة لهذا العنصر وفقدان تعديلاتها.'
          : 'هل تريد حذف ${entity.name}؟';

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      final activeId =
          tabs.isNotEmpty ? activeTab.id : null;
      final oldActiveIndex = activeIndex;

      await safFiles.deleteItem(entity.uri);

      final selectedDirectoryWasDeleted =
          selectedDirectoryUri != null &&
          deletedUris.contains(selectedDirectoryUri);

      if (selectedDirectoryWasDeleted) {
        selectedDirectoryUri = null;
        selectedDirectoryName = '';

        await _clearSavedDirectoryState();
      }

      for (final tab in affectedTabs) {
        tab.controller.dispose();
      }

      tabs.removeWhere((tab) => affectedTabs.contains(tab));

      if (tabs.isEmpty) {
        tabs.add(createTab());
        activeIndex = 0;
      } else {
        final preservedIndex = activeId == null
            ? -1
            : tabs.indexWhere((tab) => tab.id == activeId);

        if (preservedIndex != -1) {
          activeIndex = preservedIndex;
        } else {
          activeIndex = oldActiveIndex
              .clamp(0, tabs.length - 1)
              .toInt();
        }
      }

      if (!mounted) return;

      setState(() {
        _explorerRevision++;
        status = selectedDirectoryWasDeleted
            ? 'تم الحذف والعودة إلى جذر المشروع'
            : 'تم حذف العنصر';
      });

      await saveTabStateSilently();

      if (!mounted) return;

      showMessage(
        selectedDirectoryWasDeleted
            ? 'تم الحذف والعودة إلى جذر المشروع'
            : 'تم الحذف وإغلاق التبويبات التابعة',
      );
    } catch (e) {
      refreshExplorer();
      showMessage('تعذر حذف العنصر: $e');
    }
  }

  Future<void> saveCurrentToDisk() async {
    final tab = activeTab;

    if (tab.parentUri == null) {
      showMessage('هذا الملف مستقل. استخدم تصدير لحفظ التعديلات.');
      return;
    }

    try {
      await saveTabToSAF(tab);

      if (!mounted) return;

      setState(() {
        status = 'تم حفظ ${tab.fileName}';
      });

      await saveTabStateSilently();
      showMessage('تم حفظ الملف');
    } catch (e) {
      showMessage('تعذر حفظ الملف: $e');
    }
  }

  Future<void> exportFile() async {
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(activeTab.controller.text),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'تصدير الملف',
        fileName: activeTab.fileName,
        bytes: bytes,
      );
      if (path != null && mounted) {
        // Exporting a copy does not save the original SAF-backed document.
        setState(() => status = 'تم تصدير نسخة من الملف');
        showMessage('تم تصدير نسخة من الملف؛ حالة حفظ الملف الأصلي لم تتغير');
      }
    } catch (e) {
      showMessage('تعذر تصدير الملف: $e');
    }
  }

  Future<void> _addDirectoryToArchive(
    Archive archive,
    String directoryUri,
    String relativePath,
    Set<String> visitedUris,
    ProjectArchiveBudget budget, {
    int depth = 0,
  }) async {
    if (depth > 32) {
      throw FormatException('عمق مجلدات المشروع يتجاوز 32 مستوى.');
    }
    if (!visitedUris.add(directoryUri)) return;
    final children = await safFiles.listDirectory(directoryUri);
    for (final child in children) {
      final name = child.name.trim();
      if (name.isEmpty || name == '.' || name == '..' ||
          name.contains('/') || name.contains('\\')) {
        continue;
      }
      final childPath = relativePath.isEmpty ? name : '$relativePath/$name';
      if (child.isDir) {
        budget.registerEntry(childPath, byteCount: 0);
        archive.addFile(ArchiveFile('$childPath/', 0, <int>[]));
        await _addDirectoryToArchive(
          archive, child.uri, childPath, visitedUris, budget,
          depth: depth + 1,
        );
      } else {
        final bytes = await safFiles.readFile(child.uri);
        budget.registerEntry(childPath, byteCount: bytes.length);
        archive.addFile(ArchiveFile(childPath, bytes.length, bytes));
      }
    }
  }

  Future<void> _collectProjectBackup(
    String directoryUri,
    String relativePath,
    Map<String, List<int>> files,
    List<String> directories,
    Set<String> visitedUris, {
    int depth = 0,
    required List<int> budgetBytes,
  }) async {
    if (depth > 32) throw const FormatException('عمق المجلدات يتجاوز حد النسخ الاحتياطي.');
    if (!visitedUris.add(directoryUri)) throw const FormatException('تم اكتشاف حلقة أو URI مكرر في شجرة المشروع.');
    final children = await safFiles.listDirectory(directoryUri);
    for (final child in children) {
      final name = child.name;
      if (relativePath.isEmpty && child.isDir &&
          name == ProjectBackupRepository.directoryName) {
        continue; // Keep the repository outside its own snapshots.
      }
      if (name.trim().isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\')) {
        throw FormatException('اسم عنصر غير صالح أثناء النسخ الاحتياطي: ${child.name}');
      }
      final path = relativePath.isEmpty ? name : '$relativePath/$name';
      if (child.isDir) {
        directories.add(path);
        if (files.length + directories.length > ProjectBackupService.maxEntries) {
          throw const FormatException('عدد عناصر المشروع يتجاوز حد النسخ الاحتياطي.');
        }
        await _collectProjectBackup(child.uri, path, files, directories, visitedUris,
            depth: depth + 1, budgetBytes: budgetBytes);
      } else {
        final bytes = await safFiles.readFile(child.uri);
        if (bytes.length > ProjectBackupService.maxFileBytes ||
            budgetBytes[0] + bytes.length > ProjectBackupService.maxTotalBytes) {
          throw FormatException('حجم المشروع يتجاوز الحد المسموح عند الملف: $path');
        }
        files[path] = bytes;
        budgetBytes[0] += bytes.length;
        if (files.length + directories.length > ProjectBackupService.maxEntries) {
          throw const FormatException('عدد عناصر المشروع يتجاوز حد النسخ الاحتياطي.');
        }
      }
    }
  }

  Future<void> exportProjectBackup() async {
    var repositorySnapshotStored = false;
    if (projectUri == null || projectUri!.isEmpty) {
      showMessage('افتح مشروعًا أولاً لإنشاء نسخة احتياطية');
      return;
    }
    try {
      for (final tab in tabs) {
        if (tab.parentUri != null) {
          await saveTabToSAF(tab);
        } else if (!tab.isSaved) {
          throw StateError('الملف ${tab.fileName} غير مرتبط بمجلد المشروع ولم يُحفظ؛ احفظه أو صدّره قبل النسخ الاحتياطي.');
        }
      }
      final root = await safFiles.getItem(projectUri!);
      if (root == null || !root.isDir) throw Exception('مجلد المشروع غير متاح');
      final files = <String, List<int>>{};
      final directories = <String>[];
      await _collectProjectBackup(projectUri!, '', files, directories, <String>{}, budgetBytes: [0]);
      if (files.isEmpty && directories.isEmpty) throw Exception('المشروع فارغ');
      final manifest = const ProjectBackupService().encode(
        projectName: projectName,
        files: files,
        directories: directories,
      );
      final bytes = Uint8List.fromList(utf8.encode(manifest));
      await _storeProjectBackupSnapshot(
        manifestBytes: bytes,
        fileCount: files.length,
        directoryCount: directories.length,
        totalBytes: files.values.fold<int>(0, (sum, value) => sum + value.length),
      );
      repositorySnapshotStored = true;
      var safeName = projectName.trim().isEmpty
          ? 'bisho_project'
          : projectName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_. -]'), '_').replaceAll(RegExp(r'[. ]+$'), '');
      if (safeName.isEmpty || RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false).hasMatch(safeName)) {
        safeName = 'bisho_project';
      }
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'إنشاء نسخة احتياطية كاملة',
        fileName: '$safeName.bisho-backup.json',
        bytes: bytes,
      );
      if (saved != null && mounted) {
        setState(() => status = 'تم إنشاء النسخة الاحتياطية');
        showMessage('تم حفظ نقطة استعادة داخل المشروع وتصدير نسخة تشمل ${files.length} ملفًا و${directories.length} مجلدًا');
      } else if (repositorySnapshotStored && mounted) {
        showMessage('تم حفظ نقطة الاستعادة داخل المشروع؛ تم إلغاء التصدير الخارجي.');
      }
    } catch (e) {
      showMessage(repositorySnapshotStored
          ? 'تم حفظ نقطة الاستعادة داخل المشروع، لكن تعذر إكمال التصدير الخارجي: $e'
          : 'تعذر إنشاء النسخة الاحتياطية: $e');
    }
  }

  Future<String> _ensureBackupRepositoryDirectory() async {
    if (projectUri == null || projectUri!.isEmpty) {
      throw StateError('افتح مشروعًا أولاً.');
    }
    final existing = await safFiles.findChild(
      parentUri: projectUri!, name: ProjectBackupRepository.directoryName,
    );
    if (existing != null) {
      if (!existing.isDir) throw StateError('مسار مستودع النسخ مستخدم كملف.');
      return existing.uri;
    }
    return (await safFiles.createFolder(
      parentUri: projectUri!, folderName: ProjectBackupRepository.directoryName,
    )).uri;
  }

  Future<List<ProjectBackupSnapshot>> _readProjectBackupCatalog(String repositoryUri) async {
    final catalogFile = await safFiles.findChild(
      parentUri: repositoryUri, name: ProjectBackupRepository.catalogFileName,
    );
    if (catalogFile == null) return const [];
    if (catalogFile.isDir) throw const FormatException('ملف فهرس النسخ هو مجلد.');
    final bytes = await safFiles.readFile(catalogFile.uri);
    return const ProjectBackupRepository().decodeCatalog(utf8.decode(bytes));
  }

  Future<void> _writeProjectBackupCatalog(
    String repositoryUri, List<ProjectBackupSnapshot> snapshots,
  ) async {
    final existing = await safFiles.findChild(
      parentUri: repositoryUri, name: ProjectBackupRepository.catalogFileName,
    );
    await safFiles.saveFile(
      parentUri: repositoryUri,
      fileName: ProjectBackupRepository.catalogFileName,
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(
        const ProjectBackupRepository().encodeCatalog(snapshots),
      )),
      overwrite: existing != null,
    );
  }

  Future<void> _storeProjectBackupSnapshot({
    required Uint8List manifestBytes,
    required int fileCount,
    required int directoryCount,
    required int totalBytes,
  }) async {
    final repositoryUri = await _ensureBackupRepositoryDirectory();
    final repository = const ProjectBackupRepository();
    final oldSnapshots = await _readProjectBackupCatalog(repositoryUri);
    final id = 'snap_${DateTime.now().microsecondsSinceEpoch}';
    final snapshot = repository.createSnapshot(
      id: id, projectName: projectName, createdAt: DateTime.now(),
      fileCount: fileCount, directoryCount: directoryCount,
      totalBytes: totalBytes, manifestBytes: manifestBytes,
    );
    // Write immutable content first. A failed catalog update leaves only an
    // unreferenced file; it never destroys an existing restore point.
    await safFiles.saveFile(
      parentUri: repositoryUri, fileName: snapshot.fileName,
      mimeType: 'application/json', bytes: manifestBytes, overwrite: false,
    );
    final next = <ProjectBackupSnapshot>[snapshot, ...oldSnapshots]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final expired = next.length > ProjectBackupRepository.maxSnapshots
        ? next.sublist(ProjectBackupRepository.maxSnapshots) : <ProjectBackupSnapshot>[];
    final retained = next.take(ProjectBackupRepository.maxSnapshots).toList();
    await _writeProjectBackupCatalog(repositoryUri, retained);
    // Prune only after the new catalog is safely written.
    for (final item in expired) {
      final file = await safFiles.findChild(parentUri: repositoryUri, name: item.fileName);
      if (file != null && !file.isDir) await safFiles.deleteItem(file.uri);
    }
  }

  Future<void> manageProjectBackups() async {
    if (projectUri == null || projectUri!.isEmpty) {
      showMessage('افتح مشروعًا أولاً لعرض سجل النسخ.');
      return;
    }
    try {
      final repositoryUri = await _ensureBackupRepositoryDirectory();
      while (mounted) {
        final snapshots = await _readProjectBackupCatalog(repositoryUri);
        if (!mounted) return;
        if (snapshots.isEmpty) {
          showMessage('لا توجد نقاط استعادة محفوظة لهذا المشروع بعد. أنشئ نسخة احتياطية أولاً.');
          return;
        }
        final choice = await showDialog<Map<String, Object?>>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('سجل النسخ ونقاط الاستعادة'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: snapshots.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = snapshots[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore_rounded),
                    title: Text(item.createdAt.toLocal().toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${item.fileCount} ملف · ${item.directoryCount} مجلد · ${(item.totalBytes / 1048576).toStringAsFixed(2)} MB'),
                    trailing: Wrap(children: [
                      IconButton(
                        tooltip: 'استعادة هذه النقطة', icon: const Icon(Icons.settings_backup_restore_rounded),
                        onPressed: () => Navigator.pop(dialogContext, {'action': 'restore', 'snapshot': item}),
                      ),
                      IconButton(
                        tooltip: 'حذف نقطة الاستعادة', icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => Navigator.pop(dialogContext, {'action': 'delete', 'snapshot': item}),
                      ),
                    ]),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: snapshots.length < 2 ? null : () => Navigator.pop(dialogContext, {'action': 'compare'}),
                child: const Text('مقارنة نسختين'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice['action'] == 'compare') {
          await _compareProjectBackupSnapshots(repositoryUri, snapshots);
          continue;
        }
        final item = choice['snapshot'] as ProjectBackupSnapshot;
        if (choice['action'] == 'delete') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('حذف نقطة الاستعادة؟'),
              content: Text('سيتم حذف النسخة المؤرخة ${item.createdAt.toLocal()} دون التأثير على ملفات المشروع.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
              ],
            ),
          ) ?? false;
          if (!confirmed) continue;
          final latest = await _readProjectBackupCatalog(repositoryUri);
          final remaining = latest.where((entry) => entry.id != item.id).toList();
          await _writeProjectBackupCatalog(repositoryUri, remaining);
          final file = await safFiles.findChild(parentUri: repositoryUri, name: item.fileName);
          if (file != null && !file.isDir) await safFiles.deleteItem(file.uri);
          showMessage('تم حذف نقطة الاستعادة.');
          continue;
        }
        if (choice['action'] == 'restore') {
          final file = await safFiles.findChild(parentUri: repositoryUri, name: item.fileName);
          if (file == null || file.isDir) throw StateError('ملف نقطة الاستعادة غير موجود.');
          final bytes = await safFiles.readFile(file.uri);
          if (!const ProjectBackupRepository().verifyManifest(item, bytes)) {
            throw const FormatException('فشل التحقق من سلامة ملف نقطة الاستعادة.');
          }
          final backup = const ProjectBackupService().decode(utf8.decode(bytes));
          await _restoreRepositoryBackup(backup);
          return;
        }
      }
    } catch (e) {
      showMessage('تعذر فتح سجل النسخ الاحتياطية: $e');
    }
  }

  Future<void> _compareProjectBackupSnapshots(
    String repositoryUri, List<ProjectBackupSnapshot> snapshots,
  ) async {
    if (snapshots.length < 2 || !mounted) return;
    var olderId = snapshots[1].id;
    var newerId = snapshots.first.id;
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('مقارنة نقطتي استعادة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: olderId,
              decoration: const InputDecoration(labelText: 'النسخة الأقدم'),
              items: snapshots.map((item) => DropdownMenuItem(
                value: item.id,
                child: Text(item.createdAt.toLocal().toString(), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) => setDialogState(() => olderId = value ?? olderId),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: newerId,
              decoration: const InputDecoration(labelText: 'النسخة الأحدث'),
              items: snapshots.map((item) => DropdownMenuItem(
                value: item.id,
                child: Text(item.createdAt.toLocal().toString(), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) => setDialogState(() => newerId = value ?? newerId),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: olderId == newerId ? null : () => Navigator.pop(dialogContext, [olderId, newerId]),
              child: const Text('مقارنة'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final older = snapshots.firstWhere((item) => item.id == selected[0]);
    final newer = snapshots.firstWhere((item) => item.id == selected[1]);
    Future<Map<String, String>> readChecksums(ProjectBackupSnapshot snapshot) async {
      final file = await safFiles.findChild(parentUri: repositoryUri, name: snapshot.fileName);
      if (file == null || file.isDir) throw StateError('ملف النسخة ${snapshot.fileName} غير موجود.');
      final bytes = await safFiles.readFile(file.uri);
      if (!const ProjectBackupRepository().verifyManifest(snapshot, bytes)) {
        throw FormatException('فشل التحقق من سلامة النسخة ${snapshot.fileName}.');
      }
      final backup = const ProjectBackupService().decode(utf8.decode(bytes));
      return {for (final entry in backup.files.entries) entry.key: entry.value.checksum};
    }
    try {
      final oldChecksums = await readChecksums(older);
      final newChecksums = await readChecksums(newer);
      final report = const ProjectBackupRepository().compareFileChecksums(
        older: oldChecksums, newer: newChecksums,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نتيجة مقارنة النسختين'),
          content: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ملفات مضافة: ${report.added.length}'),
              Text('ملفات محذوفة: ${report.removed.length}'),
              Text('ملفات معدّلة: ${report.changed.length}'),
              Text('ملفات دون تغيير: ${report.unchanged.length}'),
              const Divider(),
              for (final entry in [
                ('مضافة', report.added), ('محذوفة', report.removed),
                ('معدّلة', report.changed),
              ]) ...[
                if (entry.$2.isNotEmpty) Text(entry.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final path in entry.$2) Text('• $path'),
              ],
            ],
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      showMessage('تعذرت مقارنة النسختين: $e');
    }
  }

  Future<void> _restoreRepositoryBackup(ProjectBackup backup) async {
    String? createdRootUri;
    try {
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد استعادة نقطة محددة'),
          content: Text(
            'المشروع: ${backup.projectName}\n'
            'الملفات: ${backup.files.length}\n'
            'المجلدات: ${backup.directories.length}\n'
            'الحجم: ${(backup.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB\n'
            'التاريخ: ${backup.createdAt.toLocal()}\n\n'
            'سيتم إنشاء مجلد جديد ولن يتم استبدال مشروع موجود.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('استعادة')),
          ],
        ),
      ) ?? false;
      if (!approved || !mounted) return;
      final parent = await safFiles.pickProjectFolder();
      if (parent == null) return;
      var folderName = backup.projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_ .-]'), '_').trim()
          .replaceAll(RegExp(r'[. ]+$'), '');
      if (folderName.isEmpty || folderName == '.' || folderName == '..' ||
          RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false).hasMatch(folderName)) {
        folderName = 'Restored_Project';
      }
      if (await safFiles.findChild(parentUri: parent.uri, name: folderName) != null) {
        folderName = '${folderName}_restored_${DateTime.now().millisecondsSinceEpoch}';
      }
      final root = await safFiles.createFolder(parentUri: parent.uri, folderName: folderName);
      createdRootUri = root.uri;
      for (final directory in backup.directories) {
        await _ensureBackupDirectory(root.uri, directory);
      }
      for (final file in backup.files.values) {
        final segments = file.path.split('/');
        final parentPath = segments.length == 1 ? '' : segments.take(segments.length - 1).join('/');
        final targetParent = parentPath.isEmpty ? root.uri : await _ensureBackupDirectory(root.uri, parentPath);
        await safFiles.saveFile(
          parentUri: targetParent, fileName: segments.last,
          mimeType: SafFileService.mimeTypeForName(segments.last),
          bytes: Uint8List.fromList(file.bytes), overwrite: false,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bisho_project_uri', root.uri);
      await prefs.setString('bisho_project_name', folderName);
      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);
      if (!mounted) return;
      setState(() {
        projectUri = root.uri; projectName = folderName;
        selectedDirectoryUri = null; selectedDirectoryName = '';
        explorerVisible = true; _explorerRevision++;
        status = 'تمت استعادة نقطة النسخة الاحتياطية';
      });
      await saveTabStateSilently();
      showMessage('تمت استعادة ${backup.files.length} ملفًا من نقطة بتاريخ ${backup.createdAt.toLocal()}');
    } catch (e) {
      if (createdRootUri != null) {
        try { await safFiles.deleteTree(createdRootUri); }
        catch (cleanupError) {
          showMessage('فشلت الاستعادة وتعذر تنظيف المجلد الجزئي: $cleanupError');
          return;
        }
      }
      showMessage('تعذرت استعادة نقطة النسخة: $e');
    }
  }

  Future<String> _ensureBackupDirectory(String rootUri, String relativePath) async {
    var current = rootUri;
    for (final segment in relativePath.split('/')) {
      final existing = await safFiles.findChild(parentUri: current, name: segment);
      if (existing != null && !existing.isDir) throw FormatException('تعارض ملف ومجلد أثناء الاستعادة: $segment');
      current = existing?.uri ?? (await safFiles.createFolder(parentUri: current, folderName: segment)).uri;
    }
    return current;
  }

  Future<void> restoreProjectBackup() async {
    String? createdRootUri;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('تعذر قراءة ملف النسخة الاحتياطية');
      final backup = const ProjectBackupService().decode(utf8.decode(bytes));
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد استعادة النسخة'),
          content: Text(
            'المشروع: ${backup.projectName}\n'
            'الملفات: ${backup.files.length}\n'
            'المجلدات: ${backup.directories.length}\n'
            'الحجم: ${(backup.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB\n'
            'تاريخ النسخة: ${backup.createdAt.toLocal()}\n\n'
            'سيتم إنشاء مجلد مشروع جديد ولن يتم استبدال الملفات الموجودة.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة الاستعادة')),
          ],
        ),
      ) ?? false;
      if (!approved || !mounted) return;
      final parent = await safFiles.pickProjectFolder();
      if (parent == null) return;
      var folderName = backup.projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_ .-]'), '_').trim()
          .replaceAll(RegExp(r'[. ]+$'), '');
      if (folderName.isEmpty || folderName == '.' || folderName == '..' ||
          RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false).hasMatch(folderName)) {
        folderName = 'Restored_Project';
      }
      if (await safFiles.findChild(parentUri: parent.uri, name: folderName) != null) {
        folderName = '${folderName}_restored_${DateTime.now().millisecondsSinceEpoch}';
      }
      final root = await safFiles.createFolder(parentUri: parent.uri, folderName: folderName);
      createdRootUri = root.uri;
      for (final directory in backup.directories) {
        await _ensureBackupDirectory(root.uri, directory);
      }
      for (final file in backup.files.values) {
        final segments = file.path.split('/');
        final parentPath = segments.length == 1 ? '' : segments.take(segments.length - 1).join('/');
        final targetParent = parentPath.isEmpty ? root.uri : await _ensureBackupDirectory(root.uri, parentPath);
        await safFiles.saveFile(
          parentUri: targetParent,
          fileName: segments.last,
          mimeType: SafFileService.mimeTypeForName(segments.last),
          bytes: Uint8List.fromList(file.bytes),
          overwrite: false,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bisho_project_uri', root.uri);
      await prefs.setString('bisho_project_name', folderName);
      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);
      if (!mounted) return;
      setState(() {
        projectUri = root.uri;
        projectName = folderName;
        selectedDirectoryUri = null;
        selectedDirectoryName = '';
        explorerVisible = true;
        _explorerRevision++;
        status = 'تمت استعادة النسخة الاحتياطية';
      });
      await saveTabStateSilently();
      showMessage('تمت استعادة ${backup.files.length} ملفًا من النسخة المؤرخة ${backup.createdAt.toLocal()}');
    } catch (e) {
      if (createdRootUri != null) {
        try {
          await safFiles.deleteTree(createdRootUri);
        } catch (cleanupError) {
          showMessage('فشلت الاستعادة والتنظيف التلقائي للمجلد الجزئي: $cleanupError');
          return;
        }
      }
      showMessage('تعذرت استعادة النسخة الاحتياطية: $e');
    }
  }

  Future<void> exportProjectArchive() async {
    if (projectUri == null || projectUri!.isEmpty) {
      showMessage('افتح مجلد مشروع أولاً لتصديره كاملاً');
      return;
    }
    try {
      await saveAllTabs();
      final root = await safFiles.getItem(projectUri!);
      if (root == null || !root.isDir) {
        throw Exception('مجلد المشروع غير متاح');
      }
      final archive = Archive();
      await _addDirectoryToArchive(
        archive, projectUri!, '', <String>{}, ProjectArchiveBudget(),
      );
      if (archive.files.isEmpty) {
        throw Exception('المشروع فارغ ولا يحتوي على ملفات للتصدير');
      }
      final archiveFiles = archive.files.where((entry) => entry.isFile).toList();
      ProjectArchiveValidator.validateArchive(
        entryCount: archive.files.length,
        files: archiveFiles.map((entry) => MapEntry(entry.name, entry.size)),
      );
      ProjectArchiveValidator.validateFilePaths(
        archiveFiles.map((entry) => entry.name),
        directoryPaths: archive.files
            .where((entry) => !entry.isFile)
            .map((entry) => entry.name),
      );
      final encoded = ZipEncoder().encode(archive);
      if (encoded.isEmpty) {
        throw Exception('تعذر إنشاء ملف ZIP');
      }
      final zipName = '${projectName.isEmpty ? 'bisho_project' : projectName}.zip';
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'تصدير المشروع كاملاً',
        fileName: zipName,
        bytes: Uint8List.fromList(encoded),
      );
      if (saved != null && mounted) {
        setState(() => status = 'تم تصدير المشروع كاملاً');
        showMessage('تم تصدير ${archive.files.length} عنصر إلى ملف ZIP');
      }
    } catch (e) {
      showMessage('تعذر تصدير المشروع: $e');
    }
  }

  Future<void> _writeArchiveEntry(
    String rootUri,
    String relativePath,
    List<int> bytes,
  ) async {
    final normalized = ProjectArchiveValidator.normalizePath(relativePath);
    final segments = normalized.split('/');
    var parentUri = rootUri;
    for (final segment in segments.take(segments.length - 1)) {
      final existing = await safFiles.findChild(parentUri: parentUri, name: segment);
      if (existing != null && !existing.isDir) {
        throw Exception('تعارض بين ملف ومجلد: $segment');
      }
      parentUri = existing?.uri ?? (await safFiles.createFolder(parentUri: parentUri, folderName: segment)).uri;
    }
    final fileName = segments.last;
    final existing = await safFiles.findChild(parentUri: parentUri, name: fileName);
    if (existing != null && existing.isDir) {
      throw Exception('يوجد مجلد باسم الملف: $fileName');
    }
    await safFiles.saveFile(
      parentUri: parentUri,
      fileName: fileName,
      mimeType: SafFileService.mimeTypeForName(fileName),
      bytes: Uint8List.fromList(bytes),
      overwrite: false,
    );
  }

  Future<void> importProjectArchive() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final input = picked.files.single;
      final zipBytes = input.bytes;
      if (zipBytes == null || zipBytes.isEmpty) {
        throw Exception('تعذر قراءة محتوى ملف ZIP');
      }
      final decoded = ZipDecoder().decodeBytes(zipBytes, verify: true);
      final archiveFiles = decoded.files.where((entry) => entry.isFile).toList();
      ProjectArchiveValidator.validateArchive(
        entryCount: decoded.files.length,
        files: archiveFiles.map((entry) => MapEntry(entry.name, entry.size)),
      );
      ProjectArchiveValidator.validateFilePaths(
        archiveFiles.map((entry) => entry.name),
        directoryPaths: decoded.files
            .where((entry) => !entry.isFile)
            .map((entry) => entry.name),
      );
      // Validate directory entries too, before creating anything on disk.
      for (final entry in decoded.files.where((item) => !item.isFile)) {
        final directoryName = entry.name.endsWith('/')
            ? entry.name.substring(0, entry.name.length - 1)
            : entry.name;
        if (directoryName.isNotEmpty) {
          ProjectArchiveValidator.normalizePath(directoryName);
        }
      }
      final parent = await safFiles.pickProjectFolder();
      if (parent == null) return;
      var folderName = input.name.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '').trim();
      folderName = folderName.replaceAll(RegExp(r'[^a-zA-Z0-9_ .-]'), '_').trim();
      if (folderName.isEmpty || folderName == '.' || folderName == '..') folderName = 'Imported_Project';
      final existing = await safFiles.findChild(parentUri: parent.uri, name: folderName);
      if (existing != null) throw Exception('يوجد مجلد بالاسم $folderName في المكان المحدد');
      final root = await safFiles.createFolder(parentUri: parent.uri, folderName: folderName);
      var importedCount = 0;
      for (final entry in decoded.files) {
        final name = entry.name.replaceAll('\\', '/');
        if (!entry.isFile) {
          final safeName = ProjectArchiveValidator.normalizePath(name);
          if (safeName.isNotEmpty) {
            final parts = safeName.split('/');
            var current = root.uri;
            for (final part in parts) {
              final found = await safFiles.findChild(parentUri: current, name: part);
              if (found != null && !found.isDir) throw Exception('تعارض في مسار ZIP');
              current = found?.uri ?? (await safFiles.createFolder(parentUri: current, folderName: part)).uri;
            }
          }
          continue;
        }
        final content = entry.content;
        final bytes = content;
        await _writeArchiveEntry(root.uri, name, bytes);
        importedCount++;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bisho_project_uri', root.uri);
      await prefs.setString('bisho_project_name', folderName);
      await prefs.remove(_savedDirectoryUriKey);
      await prefs.remove(_savedDirectoryNameKey);
      if (!mounted) return;
      setState(() {
        projectUri = root.uri;
        projectName = folderName;
        selectedDirectoryUri = null;
        selectedDirectoryName = '';
        explorerVisible = true;
        _explorerRevision++;
        status = 'تم استيراد المشروع';
      });
      await saveTabStateSilently();
      showMessage('تم استيراد $importedCount ملفًا بنجاح');
    } catch (e) {
      showMessage('تعذر استيراد المشروع المضغوط: $e');
    }
  }

  void changeLanguage(String? language) {
    if (language == null) return;

    setState(() {
      activeTab.language = language;
      activeTab.controller.language = languages[language];

      final parts = activeTab.fileName.split('.');
      final baseName = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('.')
          : activeTab.fileName;

      activeTab.fileName =
          '$baseName.${extensions[language] ?? 'txt'}';

      activeTab.isSaved = false;
      status = 'تم تغيير اللغة';
    });

    saveTabStateSilently();
  }
  Future<void> _openLocalCodeAssistant() async {
    final tab = activeTab;
    final questionController = TextEditingController();
    var report = LocalCodeAssistant.run(
      source: tab.controller.text,
      language: tab.language,
      task: LocalAssistantTask.explain,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void run(LocalAssistantTask task) {
            setDialogState(() {
              report = LocalCodeAssistant.run(
                source: tab.controller.text,
                language: tab.language,
                task: task,
              );
            });
          }

          void ask() {
            final question = questionController.text.toLowerCase();
            final task = question.contains('خطأ') || question.contains('مشكلة') ||
                    question.contains('error') || question.contains('debug')
                ? LocalAssistantTask.diagnose
                : question.contains('أمان') || question.contains('سر') ||
                    question.contains('token') || question.contains('secret')
                    ? LocalAssistantTask.security
                    : question.contains('تحسين') || question.contains('أداء') ||
                        question.contains('refactor')
                        ? LocalAssistantTask.improve
                        : LocalAssistantTask.explain;
            run(task);
          }

          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.smart_toy_rounded, color: Color(0xFFA78BFA)),
              SizedBox(width: 8),
              Expanded(child: Text('مساعد الكود المحلي')),
              Badge(label: Text('Offline')),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(dialogContext).size.height * .62,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tab.fileName} · ${tab.language}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white54)),
                const SizedBox(height: 8),
                TextField(
                  controller: questionController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => ask(),
                  decoration: InputDecoration(
                    hintText: 'اسأل عن شرح أو أخطاء أو تحسين أو أمان الكود',
                    prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'تحليل السؤال',
                      onPressed: ask,
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8)),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 5, children: [
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_rounded, size: 15),
                    label: const Text('شرح الملف'),
                    onPressed: () => run(LocalAssistantTask.explain),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.bug_report_rounded, size: 15),
                    label: const Text('فحص الأخطاء'),
                    onPressed: () => run(LocalAssistantTask.diagnose),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_fix_high_rounded, size: 15),
                    label: const Text('تحسينات'),
                    onPressed: () => run(LocalAssistantTask.improve),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.security_rounded, size: 15),
                    label: const Text('الأمان'),
                    onPressed: () => run(LocalAssistantTask.security),
                  ),
                ]),
                const Divider(height: 18),
                Text(report.title, style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF38BDF8))),
                const SizedBox(height: 5),
                Text(report.summary, style: const TextStyle(fontSize: 11, height: 1.5)),
                const SizedBox(height: 8),
                Expanded(child: ListView.separated(
                  itemCount: report.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lightbulb_outline_rounded,
                      size: 17, color: Color(0xFFFBBF24)),
                    title: SelectableText(report.items[index],
                      style: const TextStyle(fontSize: 11, height: 1.4)),
                  ),
                )),
                const Text(
                  'تحليل محلي بقواعد ثابتة — لا يستخدم نموذجًا لغويًا ولا يرسل كودك إلى الإنترنت.',
                  style: TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    questionController.dispose();
  }

  Future<void> _openFlutterPackageManager() async {
    final rootUri = projectUri;
    if (rootUri == null || rootUri.isEmpty) {
      showMessage('افتح مشروع Flutter أولاً');
      return;
    }
    try {
      final pubspec = await safFiles.findChild(parentUri: rootUri, name: 'pubspec.yaml');
      if (pubspec == null || pubspec.isDir) {
        showMessage('لم يتم العثور على pubspec.yaml في جذر المشروع');
        return;
      }
      var source = utf8.decode(await safFiles.readFile(pubspec.uri), allowMalformed: false);
      var dependencies = FlutterPackageCatalogService.readDependencies(source);
      final searchController = TextEditingController();
      var results = <String>[];
      var busy = false;
      var statusMessage = 'إدارة dependencies من pub.dev';
      var searchError = '';

      Future<void> saveSource(String updated) async {
        await safFiles.saveFile(
          parentUri: rootUri,
          fileName: 'pubspec.yaml',
          bytes: Uint8List.fromList(utf8.encode(updated)),
          overwrite: true,
        );
        source = updated;
        dependencies = FlutterPackageCatalogService.readDependencies(source);
        for (final tab in tabs.where((item) => item.fileUri == pubspec.uri)) {
          tab.controller.value = TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(offset: updated.length),
          );
          tab.isSaved = true;
        }
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final installed = dependencies.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));
            return AlertDialog(
              title: const Row(children: [
                Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8)),
                SizedBox(width: 8),
                Text('مدير حزم Flutter وDart'),
              ]),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(dialogContext).size.height * .65,
                child: Column(children: [
                  TextField(
                    controller: searchController,
                    enabled: !busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      setDialogState(() { busy = true; searchError = ''; });
                      try {
                        final found = await _packageCatalog.searchPackages(value);
                        if (context.mounted) setDialogState(() {
                          results = found;
                          statusMessage = 'نتائج pub.dev: ${found.length}';
                        });
                      } catch (error) {
                        if (context.mounted) setDialogState(() => searchError = '$error');
                      } finally {
                        if (context.mounted) setDialogState(() => busy = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'ابحث عن حزمة مثل http أو provider',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'بحث في pub.dev',
                        onPressed: busy ? null : () async {
                          final value = searchController.text.trim();
                          if (value.isEmpty) return;
                          setDialogState(() { busy = true; searchError = ''; });
                          try {
                            final found = await _packageCatalog.searchPackages(value);
                            if (context.mounted) setDialogState(() {
                              results = found;
                              statusMessage = 'نتائج pub.dev: ${found.length}';
                            });
                          } catch (error) {
                            if (context.mounted) setDialogState(() => searchError = '$error');
                          } finally {
                            if (context.mounted) setDialogState(() => busy = false);
                          }
                        },
                        icon: const Icon(Icons.travel_explore_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 15),
                    const SizedBox(width: 6),
                    Expanded(child: Text('الحزم المثبتة: ${dependencies.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                    Text('pubspec.yaml', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ]),
                  const Divider(height: 14),
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  if (searchError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(searchError, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                    ),
                  Expanded(
                    child: ListView(children: [
                      if (installed.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 5),
                          child: Text('الحزم الحالية', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF34D399))),
                        ),
                        ...installed.map((entry) {
                          final protected = entry.key == 'flutter' || entry.value.isEmpty;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined, size: 18),
                            title: Text(entry.key, style: const TextStyle(fontSize: 12)),
                            subtitle: Text(entry.value.isEmpty ? 'اعتماد SDK' : entry.value,
                              style: const TextStyle(fontSize: 10, color: Colors.white54)),
                            trailing: protected ? const Icon(Icons.lock_outline, size: 16, color: Colors.white38)
                                : IconButton(
                                    tooltip: 'إزالة من pubspec',
                                    onPressed: busy ? null : () async {
                                      final updated = FlutterPackageCatalogService.removeDependency(
                                        source, name: entry.key,
                                      );
                                      setDialogState(() { busy = true; });
                                      try {
                                        await saveSource(updated);
                                        if (context.mounted) setDialogState(() => statusMessage = 'تمت إزالة ${entry.key} من pubspec.yaml');
                                      } catch (error) {
                                        if (context.mounted) setDialogState(() => statusMessage = 'تعذر الحفظ: $error');
                                      } finally {
                                        if (context.mounted) setDialogState(() => busy = false);
                                      }
                                    },
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 19),
                                  ),
                          );
                        }),
                      ],
                      if (results.isNotEmpty) ...[
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 5),
                          child: Text('نتائج pub.dev', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF38BDF8))),
                        ),
                        ...results.map((name) {
                          final alreadyInstalled = dependencies.containsKey(name);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.extension_outlined, color: Color(0xFF60A5FA), size: 19),
                            title: Text(name, style: const TextStyle(fontSize: 12)),
                            subtitle: Text(alreadyInstalled ? 'مضافة إلى المشروع' : 'إضافة أحدث إصدار مستقر',
                              style: const TextStyle(fontSize: 10, color: Colors.white54)),
                            trailing: alreadyInstalled
                                ? const Icon(Icons.check_circle, color: Color(0xFF34D399), size: 19)
                                : IconButton(
                                    tooltip: 'إضافة الحزمة',
                                    onPressed: busy ? null : () async {
                                      setDialogState(() { busy = true; statusMessage = 'جارٍ جلب أحدث إصدار من $name…'; });
                                      try {
                                        final info = await _packageCatalog.packageInfo(name);
                                        final updated = FlutterPackageCatalogService.addDependency(
                                          source, name: info.name, version: info.latestVersion,
                                        );
                                        await saveSource(updated);
                                        if (context.mounted) setDialogState(() => statusMessage = 'تمت إضافة $name: ^${info.latestVersion} إلى pubspec.yaml');
                                      } catch (error) {
                                        if (context.mounted) setDialogState(() => statusMessage = 'تعذرت إضافة الحزمة: $error');
                                      } finally {
                                        if (context.mounted) setDialogState(() => busy = false);
                                      }
                                    },
                                    icon: const Icon(Icons.add_circle, color: Color(0xFF38BDF8), size: 21),
                                  ),
                          );
                        }),
                      ],
                      if (installed.isEmpty && results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: Text('ابحث عن حزمة أو راجع dependencies في المشروع')),
                        ),
                    ]),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(statusMessage,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.white60)),
                  ),
                  const Text('يتم تحديث pubspec.yaml فقط؛ حلّ الحزم يتم عبر Flutter pub get في بيئة البناء.',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
                ]),
              ),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
              ],
            );
          },
        ),
      );
      searchController.dispose();
    } catch (error) {
      showMessage('تعذر فتح مدير الحزم: $error');
    }
  }

  Future<void> _openWidgetTreeInspector() async {
    final tab = activeTab;
    if (tab.language != 'Dart' && !tab.fileName.toLowerCase().endsWith('.dart')) {
      showMessage('مستكشف Widget Tree يعمل مع ملفات Dart/Flutter فقط');
      return;
    }
    final nodes = FlutterWidgetTreeAnalyzer.analyze(tab.controller.text);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.account_tree_rounded, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Flutter Widget Inspector')),
          Text('${nodes.length}', style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(dialogContext).size.height * .58,
          child: nodes.isEmpty
              ? const Center(child: Text('لم يتم العثور على Widgets معروفة في الملف الحالي'))
              : Column(children: [
                  const Text(
                    'شجرة بنية المصدر — تحليل ساكن، وليست بيانات تشغيل حي.',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: ListView.builder(
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      return Padding(
                        padding: EdgeInsetsDirectional.only(start: node.depth * 13.0),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            node.parentIndex == null
                                ? Icons.account_tree_rounded
                                : Icons.subdirectory_arrow_right_rounded,
                            color: node.parentIndex == null
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFFA78BFA),
                            size: 18,
                          ),
                          title: Text(node.name,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          subtitle: Text('السطر ${node.line}',
                            style: const TextStyle(fontSize: 10, color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(dialogContext);
                            final offset = node.offset.clamp(0, tab.controller.text.length).toInt();
                            tab.controller.selection = TextSelection.collapsed(offset: offset);
                            showMessage('تم الانتقال إلى ${node.name} في السطر ${node.line}');
                          },
                        ),
                      );
                    },
                  )),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _openGitHubManager() async {
    if (projectUri == null || projectUri!.isEmpty) {
      showMessage('افتح مشروع Flutter أولاً قبل ربط GitHub');
      return;
    }
    final repositoryController = TextEditingController(text: 'bisho-project');
    final descriptionController = TextEditingController(text: 'Flutter project created with Bisho IDE');
    final tokenController = TextEditingController();
    var token = await _githubService.readToken();
    GitHubAccount? account;
    var connectionMessage = '';
    if (token != null && token.isNotEmpty) {
      try {
        account = await _githubService.verifyToken(token);
      } catch (error) {
        connectionMessage = 'تعذر التحقق من الرمز المحفوظ: $error';
        token = null;
      }
    }
    var isPrivate = true;
    var busy = false;
    var progress = '';
    String? repositoryUrl;
    var uploadedFiles = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: !busy,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.account_tree_rounded, color: Color(0xFF34D399)),
            SizedBox(width: 9),
            Text('GitHub داخل Bisho IDE'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (account != null)
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12352E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF237A5B)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF34D399)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('متصل بالحساب ${account!.login}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                      TextButton(
                        onPressed: busy ? null : () async {
                          await _githubService.disconnect();
                          setDialogState(() {
                            account = null;
                            token = null;
                            connectionMessage = 'تم فصل حساب GitHub من هذا الجهاز';
                          });
                        },
                        child: const Text('فصل'),
                      ),
                    ]),
                  )
                else ...[
                  const Text('رمز الوصول الشخصي (PAT)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: tokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'ghp_… أو github_pat_…',
                      prefixIcon: Icon(Icons.key_rounded),
                      helperText: 'يُحفظ بعد التحقق داخل التخزين الآمن على Android فقط',
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: busy ? null : () async {
                        final entered = tokenController.text.trim();
                        if (entered.isEmpty) {
                          setDialogState(() => connectionMessage = 'أدخل رمز GitHub أولاً');
                          return;
                        }
                        setDialogState(() { busy = true; connectionMessage = 'جارٍ التحقق من الرمز…'; });
                        try {
                          final verified = await _githubService.verifyToken(entered);
                          await _githubService.saveToken(entered);
                          if (!context.mounted) return;
                          setDialogState(() {
                            token = entered;
                            account = verified;
                            connectionMessage = 'تم التحقق وحفظ الرمز بأمان';
                          });
                          tokenController.clear();
                        } catch (error) {
                          if (context.mounted) setDialogState(() => connectionMessage = 'فشل التحقق: $error');
                        } finally {
                          if (context.mounted) setDialogState(() => busy = false);
                        }
                      },
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('تحقق واربط الحساب'),
                    ),
                  ),
                ],
                if (connectionMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(connectionMessage,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF93C5FD))),
                  ),
                const Divider(),
                const Text('رفع مشروع Flutter إلى مستودع جديد',
                  style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                TextField(
                  controller: repositoryController,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستودع',
                    prefixIcon: Icon(Icons.folder_copy_outlined),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: descriptionController,
                  enabled: !busy,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'وصف المستودع'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPrivate,
                  onChanged: busy ? null : (value) => setDialogState(() => isPrivate = value),
                  title: const Text('مستودع خاص'),
                  subtitle: const Text('لا يظهر للعامة'),
                ),
                if (progress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      if (busy) const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                      if (busy) const SizedBox(width: 9),
                      Expanded(child: Text(progress, style: const TextStyle(fontSize: 11))),
                    ]),
                  ),
                if (repositoryUrl != null) ...[
                  const SizedBox(height: 10),
                  const Text('تم رفع المشروع بنجاح',
                    style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800)),
                  SelectableText(repositoryUrl!, textDirection: TextDirection.ltr),
                  Text('عدد الملفات: $uploadedFiles',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: repositoryUrl!)),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('نسخ الرابط'),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: busy || token == null || account == null || repositoryUrl != null
                  ? null
                  : () async {
                      final name = repositoryController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => progress = 'اكتب اسم المستودع أولاً');
                        return;
                      }
                      setDialogState(() { busy = true; progress = 'جارٍ تجهيز المشروع…'; });
                      try {
                        final result = await _githubService.createAndPushProject(
                          token: token!,
                          projectUri: projectUri!,
                          repositoryName: name,
                          description: descriptionController.text.trim(),
                          isPrivate: isPrivate,
                          workflowFile: 'build-android.yml',
                          safFiles: safFiles,
                          onProgress: (message) {
                            if (context.mounted) setDialogState(() => progress = message);
                          },
                        );
                        if (!context.mounted) return;
                        setDialogState(() {
                          repositoryUrl = result.htmlUrl;
                          uploadedFiles = result.uploadedFiles;
                          progress = 'تم الرفع إلى الفرع ${result.branch}';
                        });
                      } catch (error) {
                        if (context.mounted) setDialogState(() => progress = 'تعذر الرفع: $error');
                      } finally {
                        if (context.mounted) setDialogState(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('إنشاء المستودع ورفع المشروع'),
            ),
          ],
        ),
      ),
    );
    repositoryController.dispose();
    descriptionController.dispose();
    tokenController.dispose();
  }

  Future<void> _openSplitEditor() async {
    if (tabs.length < 2) {
      showMessage('افتح ملفًا ثانيًا أولاً ثم فعّل تقسيم المحرر');
      await openFile();
      if (!mounted || tabs.length < 2) return;
    }
    final candidates = tabs.where((item) => item.id != activeTab.id).toList();
    if (candidates.isEmpty) {
      showMessage('لا يوجد ملف آخر لعرضه في الجزء الثاني');
      return;
    }
    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اختر الملف للجزء الثاني'),
        content: SizedBox(
          width: double.maxFinite,
          height: 260,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final item = candidates[index];
              return ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF38BDF8)),
                title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.language),
                onTap: () => Navigator.pop(dialogContext, item.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
        ],
      ),
    );
    if (selectedId == null || !mounted) return;
    setState(() {
      _splitTabId = selectedId;
      status = 'تم تفعيل المحرر المقسّم';
    });
  }

  void _closeSplitEditor() {
    setState(() {
      _splitTabId = null;
      status = 'تم إغلاق العرض المقسّم';
    });
  }

  Widget _buildSplitEditorPanel() {
    final secondaryIndex = tabs.indexWhere((item) => item.id == _splitTabId);
    if (secondaryIndex < 0 || tabs.length < 2 || tabs[secondaryIndex].id == activeTab.id) {
      return const SizedBox.shrink();
    }
    final primary = activeTab;
    final secondary = tabs[secondaryIndex];

    Widget pane(EditorTab item, {required bool isPrimary}) {
      return Container(
        height: 210,
        decoration: BoxDecoration(
          color: const Color(0xFF080D19),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: isPrimary ? const Color(0xFF38BDF8) : const Color(0xFFA78BFA)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF142239),
            child: Row(children: [
              Icon(Icons.code_rounded, size: 15,
                color: isPrimary ? const Color(0xFF38BDF8) : const Color(0xFFA78BFA)),
              const SizedBox(width: 7),
              Expanded(child: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              Text(item.isSaved ? 'محفوظ' : '●', style: TextStyle(
                color: item.isSaved ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                fontSize: 9,
              )),
            ]),
          ),
          Expanded(child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: CodeField(
              key: ValueKey('split-${item.id}'),
              controller: item.controller,
              expands: true,
              wrap: _wordWrap,
              padding: const EdgeInsets.all(9),
              textStyle: TextStyle(fontFamily: 'monospace', fontSize: (_editorFontSize - 2).clamp(10.0, 18.0).toDouble()),
              gutterStyle: const GutterStyle(
                showLineNumbers: true,
                showErrors: true,
                showFoldingHandles: true,
              ),
            ),
          )),
        ]),
      );
    }

    return _dashboardPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.vertical_split_rounded, color: Color(0xFF38BDF8), size: 19),
          const SizedBox(width: 8),
          const Expanded(child: Text('المحرر المقسّم', style: TextStyle(fontWeight: FontWeight.w800))),
          DropdownButton<String>(
            value: secondary.id,
            isDense: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF18263B),
            items: tabs.where((item) => item.id != primary.id).map((item) =>
              DropdownMenuItem(value: item.id, child: SizedBox(width: 130, child: Text(item.fileName,
                maxLines: 1, overflow: TextOverflow.ellipsis)))
            ).toList(),
            onChanged: (value) => setState(() => _splitTabId = value),
          ),
          IconButton(
            tooltip: 'إغلاق التقسيم',
            visualDensity: VisualDensity.compact,
            onPressed: _closeSplitEditor,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 620) {
            return Row(children: [
              Expanded(child: pane(primary, isPrimary: true)),
              const SizedBox(width: 9),
              Expanded(child: pane(secondary, isPrimary: false)),
            ]);
          }
          return Column(children: [
            pane(primary, isPrimary: true),
            const SizedBox(height: 9),
            pane(secondary, isPrimary: false),
          ]);
        }),
      ]),
    );
  }

  Future<void> _openCommandPalette() async {
    final commands = <_PaletteCommand>[
      _PaletteCommand(title: 'ملف جديد', description: 'إنشاء تبويب وملف فارغ', icon: Icons.note_add_rounded, run: createNewTab, keywords: 'new file'),
      _PaletteCommand(title: 'مشروع جديد', description: 'إنشاء مشروع باستخدام المعالج', icon: Icons.create_new_folder_rounded, run: createNewProject, keywords: 'new project'),
      _PaletteCommand(title: 'فتح ملف', description: 'اختيار ملف من الجهاز', icon: Icons.file_open_rounded, run: openFile, keywords: 'open file'),
      _PaletteCommand(title: 'فتح مشروع', description: 'اختيار مجلد مشروع', icon: Icons.folder_open_rounded, run: openProjectFolder, keywords: 'open folder'),
      _PaletteCommand(title: 'مدير المشاريع', description: 'المشاريع الأخيرة والمفضلة', icon: Icons.workspaces_rounded, run: showProjectManager, keywords: 'projects'),
      _PaletteCommand(title: 'إدارة GitHub', description: 'ربط الحساب ورفع مشروع Flutter', icon: Icons.account_tree_rounded, run: _openGitHubManager, keywords: 'git github repository push'),
      _PaletteCommand(title: 'Flutter Widget Inspector', description: 'استعراض شجرة Widgets والتنقل للأسطر', icon: Icons.account_tree_rounded, run: _openWidgetTreeInspector, keywords: 'widget tree inspector flutter'),
      _PaletteCommand(title: 'مدير حزم Flutter وDart', description: 'البحث في pub.dev وإدارة dependencies', icon: Icons.inventory_2_rounded, run: _openFlutterPackageManager, keywords: 'pub package dependencies pub.dev'),
      _PaletteCommand(title: 'مساعد الكود المحلي', description: 'شرح وفحص وتحسين وأمان دون اتصال', icon: Icons.smart_toy_rounded, run: _openLocalCodeAssistant, keywords: 'local assistant ai explain debug security'),
      _PaletteCommand(title: 'حفظ الملف', description: 'حفظ التعديلات الحالية', icon: Icons.save_rounded, run: saveCurrentToDisk, keywords: 'save'),
      _PaletteCommand(title: 'حفظ جميع الملفات', description: 'حفظ كل التبويبات المفتوحة', icon: Icons.save_as_rounded, run: saveAllTabs, keywords: 'save all'),
      _PaletteCommand(title: 'بحث واستبدال', description: 'البحث داخل الملف أو المشروع', icon: Icons.find_replace_rounded, run: () => searchCode(startInReplaceMode: true), keywords: 'search replace find'),
      _PaletteCommand(title: 'بحث في المشروع', description: 'البحث داخل جميع الملفات', icon: Icons.search_rounded, run: searchCode, keywords: 'find in files'),
      _PaletteCommand(title: 'تقسيم المحرر', description: 'تحرير ملفين جنبًا إلى جنب', icon: Icons.vertical_split_rounded, run: _openSplitEditor, keywords: 'split editor side by side'),
      _PaletteCommand(title: 'الإكمال البرمجي', description: 'اقتراح الكلمات والمقاطع', icon: Icons.auto_awesome_rounded, run: showCodeCompletions, keywords: 'autocomplete intellisense'),
      _PaletteCommand(title: 'الطرفية', description: 'فتح جلسة الأوامر', icon: Icons.terminal_rounded, run: _showTerminalPanel, keywords: 'terminal shell console'),
      _PaletteCommand(title: 'فحص المشكلات', description: 'عرض التشخيصات والإصلاحات', icon: Icons.bug_report_rounded, run: _openDiagnosticsPanel, keywords: 'diagnostics errors lint'),
      _PaletteCommand(title: 'مساعد إصلاح الأخطاء', description: 'اقتراح تعديلات مع معاينة', icon: Icons.auto_fix_high_rounded, run: _openFixAssistant, keywords: 'fix errors'),
      _PaletteCommand(title: 'تنسيق الكود', description: 'معاينة تنسيق النص', icon: Icons.format_align_left_rounded, run: _openFormatPreview, keywords: 'format code'),
      _PaletteCommand(title: 'سجل إصدارات الملف', description: 'استعادة نسخة سابقة', icon: Icons.history_rounded, run: _openVersionHistory, keywords: 'history restore'),
      _PaletteCommand(title: 'فحص جودة المشروع', description: 'تحليل بنية المشروع', icon: Icons.health_and_safety_rounded, run: _openProjectInsightsPanel, keywords: 'project health'),
      _PaletteCommand(title: 'الإضافات والأدوات', description: 'فتح مركز الإضافات المدمجة', icon: Icons.extension_rounded, run: _showPluginsHub, keywords: 'extensions plugins'),
      _PaletteCommand(title: 'شاشة المحرر الكاملة', description: 'توسيع مساحة تحرير الكود', icon: Icons.fullscreen_rounded, run: _openEditorFullScreen, keywords: 'fullscreen editor'),
      _PaletteCommand(title: 'تبديل المظهر', description: 'فاتح أو داكن', icon: Icons.palette_rounded, run: BishoThemeController.toggle, keywords: 'theme appearance'),
    ];

    final controller = TextEditingController();
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = EditorCommandPalette.filter(
            commands,
            query: query,
            searchableText: (command) => command.searchableText,
          );
          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.keyboard_command_key_rounded, color: Color(0xFF38BDF8)),
              SizedBox(width: 9),
              Text('لوحة الأوامر'),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              height: 390,
              child: Column(children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (value) => setDialogState(() => query = value),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن أمر…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty ? null : IconButton(
                      onPressed: () {
                        controller.clear();
                        setDialogState(() => query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('لا توجد أوامر مطابقة'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final command = filtered[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(command.icon, color: const Color(0xFF38BDF8)),
                              title: Text(command.title),
                              subtitle: Text(command.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () async {
                                Navigator.pop(dialogContext);
                                await command.run();
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 5),
                const Text('اكتب للبحث ثم اختر الأمر المطلوب', style: TextStyle(fontSize: 11, color: Colors.white54)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
    controller.dispose();
  }

  Future<void> searchCode({bool startInReplaceMode = false}) async {
    final findController = TextEditingController();
    final replaceController = TextEditingController();
    var replaceMode = startInReplaceMode;

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('البحث والاستبدال'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: findController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'بحث عن',
                  hintText: 'اكتب النص المطلوب',
                ),
              ),
              if (replaceMode)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: replaceController,
                    decoration: const InputDecoration(
                      labelText: 'استبدال بـ',
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setDialogState(
                    () => replaceMode = !replaceMode,
                  ),
                  icon: Icon(replaceMode ? Icons.search : Icons.find_replace),
                  label: Text(
                    replaceMode ? 'إخفاء الاستبدال' : 'إظهار الاستبدال',
                  ),
                ),
              ),
              if (replaceMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, {
                      'find': findController.text,
                      'replace': replaceController.text,
                      'mode': 'projectReplace',
                    }),
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    label: const Text('استبدال في جميع ملفات المشروع'),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, {
                    'find': findController.text,
                    'mode': 'project',
                  }),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('البحث في جميع ملفات المشروع'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'find': findController.text,
                'replace': replaceController.text,
                'mode': replaceMode ? 'replace' : 'find',
              }),
              child: Text(replaceMode ? 'استبدال الكل' : 'بحث'),
            ),
          ],
        ),
      ),
    );

    findController.dispose();
    replaceController.dispose();

    if (result == null) return;
    final query = result['find'] ?? '';
    if (query.isEmpty) return;

    if (result['mode'] == 'project') {
      await searchProjectFiles(query);
      return;
    }
    if (result['mode'] == 'projectReplace') {
      final replacement = result['replace'] ?? '';
      if (replacement == query) {
        showMessage('النص البديل مطابق لنص البحث؛ لا توجد تغييرات');
        return;
      }
      await _replaceProjectFiles(query, replacement);
      return;
    }

    final source = activeTab.controller.text;
    if (result['mode'] == 'replace') {
      final replacement = result['replace'] ?? '';
      final matches = query.allMatches(source).length;
      if (matches == 0) {
        showMessage('لم يتم العثور على النص');
        return;
      }
      activeTab.controller.text = source.replaceAll(query, replacement);
      activeTab.controller.selection = TextSelection.collapsed(
        offset: activeTab.controller.text.length,
      );
      showMessage('تم استبدال $matches تطابق');
      return;
    }

    final currentSelection = activeTab.controller.selection;
    final searchFrom = currentSelection.isValid
        ? currentSelection.extentOffset.clamp(0, source.length).toInt()
        : 0;
    var start = source.indexOf(query, searchFrom);
    if (start == -1 && searchFrom > 0) {
      start = source.indexOf(query);
    }
    if (start == -1) {
      showMessage('لم يتم العثور على النص');
      return;
    }
    activeTab.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + query.length,
    );
    showMessage('تم العثور على النص');
  }

  Future<void> _replaceProjectFiles(String query, String replacement) async {
    final rootUri = projectUri;
    if (rootUri == null || rootUri.isEmpty) {
      showMessage('افتح مجلد المشروع أولاً');
      return;
    }
    final extensions = <String>{
      'dart', 'py', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'html', 'htm',
      'css', 'scss', 'sass', 'json', 'xml', 'yaml', 'yml', 'md', 'markdown',
      'txt', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cpp', 'hpp', 'sql',
      'sh', 'bash', 'go', 'rs', 'php', 'toml', 'ini', 'gradle', 'properties',
    };
    final candidates = <({
      SafDocumentFile file,
      String parentUri,
      String path,
      String updated,
      int count,
    })>[];
    var scanned = 0;
    var skipped = 0;
    var totalMatches = 0;
    const maxFiles = 500;
    const maxBytes = 1024 * 1024;
    const ignored = {
      '.git', '.dart_tool', '.idea', '.gradle', 'build',
      'node_modules', '.bisho-backups',
    };

    Future<void> scan(String directoryUri, String prefix) async {
      if (scanned >= maxFiles || candidates.length >= 200) return;
      List<SafDocumentFile> children;
      try {
        children = await safFiles.listDirectory(directoryUri);
      } catch (_) {
        skipped++;
        return;
      }
      for (final child in children) {
        if (scanned >= maxFiles || candidates.length >= 200) break;
        final path = prefix.isEmpty ? child.name : '$prefix/${child.name}';
        if (child.isDir) {
          if (!ignored.contains(child.name.toLowerCase())) {
            await scan(child.uri, path);
          }
          continue;
        }
        final dot = child.name.lastIndexOf('.');
        final ext = dot < 0 ? '' : child.name.substring(dot + 1).toLowerCase();
        if (!extensions.contains(ext)) continue;
        scanned++;
        try {
          final bytes = await safFiles.readFile(child.uri);
          if (bytes.length > maxBytes) {
            skipped++;
            continue;
          }
          final source = utf8.decode(bytes, allowMalformed: false);
          final result = ProjectTextReplacement.replaceAll(
            source: source,
            query: query,
            replacement: replacement,
            caseSensitive: true,
          );
          if (result.replacements == 0) continue;
          candidates.add((
            file: child,
            parentUri: directoryUri,
            path: path,
            updated: result.text,
            count: result.replacements,
          ));
          totalMatches += result.replacements;
        } catch (_) {
          skipped++;
        }
      }
    }

    showMessage('جارٍ فحص ملفات المشروع قبل الاستبدال...');
    await scan(rootUri, '');
    if (!mounted) return;
    if (candidates.isEmpty) {
      showMessage('لم يتم العثور على تطابقات قابلة للاستبدال');
      return;
    }

    final affectedUris = candidates.map((item) => item.file.uri).toSet();
    final unsaved = tabs.where((tab) =>
      tab.fileUri != null && affectedUris.contains(tab.fileUri) && !tab.isSaved
    ).toList();
    if (unsaved.isNotEmpty) {
      showMessage('احفظ الملفات المفتوحة المعدّلة أولاً ثم أعد الاستبدال؛ لم يتم تغيير أي ملف');
      return;
    }

    final preview = candidates.take(8).map((item) =>
      '${item.path}  ·  ${item.count} استبدال'
    ).join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد استبدال ملفات المشروع'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سيتم استبدال $totalMatches تطابقًا في ${candidates.length} ملف.'),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 190),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(child: Text(
                  preview + (candidates.length > 8 ? '\n... و${candidates.length - 8} ملفات أخرى' : ''),
                  style: const TextStyle(fontSize: 12),
                )),
              ),
              const SizedBox(height: 8),
              const Text('الاستبدال حساس لحالة الأحرف، ولن يشمل مجلدات البناء أو .git.'),
              if (scanned >= maxFiles || candidates.length >= 200 || skipped > 0)
                Text('ملاحظة: فُحص $scanned ملفًا وتُخطّي $skipped ملفًا بسبب الحدود أو تعذّر القراءة.',
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('تأكيد الاستبدال'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var savedFiles = 0;
    var savedMatches = 0;
    Object? failure;
    for (final item in candidates) {
      try {
        await safFiles.saveFile(
          parentUri: item.parentUri,
          fileName: item.file.name,
          bytes: Uint8List.fromList(utf8.encode(item.updated)),
          overwrite: true,
        );
        savedFiles++;
        savedMatches += item.count;
        for (final tab in tabs.where((tab) => tab.fileUri == item.file.uri)) {
          tab.controller.value = TextEditingValue(
            text: item.updated,
            selection: TextSelection.collapsed(offset: item.updated.length),
          );
          tab.isSaved = true;
        }
      } catch (error) {
        failure = error;
        break;
      }
    }
    if (mounted) {
      setState(() {
        status = failure == null ? 'تم استبدال نص المشروع' : 'اكتمل الاستبدال جزئيًا';
      });
      final suffix = failure == null
          ? ''
          : '، وتوقف بسبب خطأ: $failure';
      showMessage('تم تحديث $savedFiles من ${candidates.length} ملفًا ($savedMatches استبدال)$suffix');
    }
  }

  Future<void> searchProjectFiles(String query) async {
    final rootUri = projectUri;
    if (rootUri == null || rootUri.isEmpty) {
      showMessage('افتح مجلد المشروع أولاً للبحث داخله');
      return;
    }

    final searchableExtensions = <String>{
      'dart', 'py', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'html', 'htm',
      'css', 'scss', 'sass', 'json', 'xml', 'yaml', 'yml', 'md', 'markdown',
      'txt', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cpp', 'hpp', 'sql',
      'sh', 'bash', 'go', 'rs', 'php', 'toml', 'ini', 'gradle', 'properties',
    };
    final results = <_ProjectSearchResult>[];
    var visitedFiles = 0;
    var skippedFiles = 0;
    const maxFiles = 500;
    const maxFileBytes = 1024 * 1024;
    const ignoredDirectories = {
      '.git', '.dart_tool', '.idea', '.gradle', 'build',
      'node_modules', '.bisho-backups',
    };
    final needle = query.trim().toLowerCase();

    Future<void> scanDirectory(
      String directoryUri,
      String relativeDirectory,
    ) async {
      if (visitedFiles >= maxFiles || results.length >= 200) return;
      List<SafDocumentFile> items;
      try {
        items = await safFiles.listDirectory(directoryUri);
      } catch (_) {
        skippedFiles++;
        return;
      }

      for (final item in items) {
        if (visitedFiles >= maxFiles || results.length >= 200) break;
        final relativePath = relativeDirectory.isEmpty
            ? item.name
            : '$relativeDirectory/${item.name}';
        if (item.isDir) {
          if (ignoredDirectories.contains(item.name.toLowerCase())) continue;
          await scanDirectory(item.uri, relativePath);
          continue;
        }

        final matchesFileName = item.name.toLowerCase().contains(needle) ||
            relativePath.toLowerCase().contains(needle);
        final dot = item.name.lastIndexOf('.');
        final extension = dot < 0
            ? ''
            : item.name.substring(dot + 1).toLowerCase();
        final canReadContent = searchableExtensions.contains(extension);
        if (!canReadContent) {
          if (matchesFileName) {
            results.add(_ProjectSearchResult(
              file: item,
              parentUri: directoryUri,
              relativePath: relativePath,
              matchingLines: const [],
            ));
          }
          continue;
        }

        visitedFiles++;
        try {
          final bytes = await safFiles.readFile(item.uri);
          if (bytes.length > maxFileBytes) {
            skippedFiles++;
            if (matchesFileName) {
              results.add(_ProjectSearchResult(
                file: item,
                parentUri: directoryUri,
                relativePath: relativePath,
                matchingLines: const [],
              ));
            }
            continue;
          }
          final content = utf8.decode(bytes, allowMalformed: true);
          final lines = content.split('\n');
          final matchingLines = <int>[];
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].toLowerCase().contains(needle)) {
              matchingLines.add(i + 1);
              if (matchingLines.length >= 20) break;
            }
          }
          if (matchesFileName || matchingLines.isNotEmpty) {
            results.add(_ProjectSearchResult(
              file: item,
              parentUri: directoryUri,
              relativePath: relativePath,
              matchingLines: matchingLines,
            ));
          }
        } catch (_) {
          skippedFiles++;
          if (matchesFileName) {
            results.add(_ProjectSearchResult(
              file: item,
              parentUri: directoryUri,
              relativePath: relativePath,
              matchingLines: const [],
            ));
          }
        }
      }
    }

    showMessage('جارٍ البحث في أسماء الملفات ومحتوياتها...');
    await scanDirectory(rootUri, '');
    results.sort((a, b) => a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('نتائج البحث: ${results.length}'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(dialogContext).size.height * 0.55,
          child: results.isEmpty
              ? const Center(child: Text('لم يتم العثور على تطابقات'))
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    final lineSummary = result.matchingLines.isEmpty
                        ? 'تطابق في اسم الملف أو مساره'
                        : 'الأسطر: ${result.matchingLines.take(5).join(', ')}'
                            '${result.matchingLines.length > 5 ? ' ...' : ''}';
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        result.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${result.relativePath}\n$lineSummary',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        await openProjectFile(result.file, result.parentUri);
                        final opened = tabs.indexWhere(
                          (tab) => tab.fileUri == result.file.uri,
                        );
                        if (opened >= 0) {
                          selectTab(opened);
                          final text = tabs[opened].controller.text;
                          final offset = text.toLowerCase().indexOf(needle);
                          if (offset >= 0) {
                            tabs[opened].controller.selection = TextSelection(
                              baseOffset: offset,
                              extentOffset: offset + query.length,
                            );
                          }
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final limitNote = visitedFiles >= maxFiles || results.length >= 200
        ? ' (توقف البحث عند بلوغ الحد الوقائي)'
        : '';
    showMessage(
      'اكتمل البحث: فُحص $visitedFiles ملفًا، وتُخطّي $skippedFiles$limitNote',
    );
  }

  void _applyHistoryText(EditorTab tab, String value) {
    _historyApplying.add(tab.id);
    tab.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _historyApplying.remove(tab.id);
    setState(() {
      tab.isSaved = false;
      status = 'تعديل في سجل التراجع';
    });
  }

  void undoCodeEdit() {
    final tab = activeTab;
    final history = _undoHistory.putIfAbsent(
      tab.id,
      () => <String>[tab.controller.text],
    );
    if (history.length <= 1) {
      showMessage('لا توجد تعديلات للتراجع عنها');
      return;
    }
    final current = history.removeLast();
    _redoHistory.putIfAbsent(tab.id, () => <String>[]).add(current);
    _applyHistoryText(tab, history.last);
  }

  void redoCodeEdit() {
    final tab = activeTab;
    final redo = _redoHistory.putIfAbsent(tab.id, () => <String>[]);
    if (redo.isEmpty) {
      showMessage('لا توجد تعديلات لإعادتها');
      return;
    }
    final next = redo.removeLast();
    _undoHistory.putIfAbsent(tab.id, () => <String>[]).add(next);
    _applyHistoryText(tab, next);
  }

  void _applyLineEdit(EditorLineEditResult? result, String successMessage) {
    if (result == null) {
      showMessage('لا يمكن تنفيذ العملية في هذا الموضع');
      return;
    }
    final tab = activeTab;
    if (result.text == tab.controller.text) return;
    tab.controller.value = TextEditingValue(
      text: result.text,
      selection: result.selection,
    );
    setState(() {
      tab.isSaved = false;
      status = successMessage;
    });
    _scheduleTabStateSave();
  }

  void duplicateSelectedLines() {
    final tab = activeTab;
    _applyLineEdit(
      EditorLineActions.duplicateSelectedLines(
        text: tab.controller.text,
        selection: tab.controller.selection,
      ),
      'تم تكرار الأسطر المحددة',
    );
  }

  void moveCurrentLineUp() {
    final tab = activeTab;
    _applyLineEdit(
      EditorLineActions.moveCurrentLine(
        text: tab.controller.text,
        selection: tab.controller.selection,
        down: false,
      ),
      'تم نقل السطر للأعلى',
    );
  }

  void moveCurrentLineDown() {
    final tab = activeTab;
    _applyLineEdit(
      EditorLineActions.moveCurrentLine(
        text: tab.controller.text,
        selection: tab.controller.selection,
        down: true,
      ),
      'تم نقل السطر للأسفل',
    );
  }

  void toggleSelectedLineComments() {
    final tab = activeTab;
    _applyLineEdit(
      EditorLineActions.toggleLineComments(
        text: tab.controller.text,
        selection: tab.controller.selection,
        language: tab.language,
      ),
      'تم تبديل التعليق على الأسطر',
    );
  }

  void jumpToMatchingBracket() {
    final tab = activeTab;
    final selection = tab.controller.selection;
    final cursor = selection.isValid
        ? selection.extentOffset
        : tab.controller.text.length;
    final match = EditorBracketMatcher.findMatchingOffset(
      source: tab.controller.text,
      cursorOffset: cursor,
      language: tab.language,
    );
    if (match == null) {
      setState(() => status = 'لم يتم العثور على قوس مطابق');
      return;
    }
    tab.controller.selection = TextSelection.collapsed(offset: match);
    setState(() => status = 'تم الانتقال إلى القوس المطابق');
    _scheduleTabStateSave();
  }

  String? _diagnosticsCacheTabId;
  String? _diagnosticsCacheLanguage;
  String? _diagnosticsCacheSource;
  List<String> _diagnosticsCache = const <String>[];

  /// Memoised per tab/language/text so repeated rebuilds do not re-parse the
  /// whole file when nothing changed.
  List<String> _getCurrentDiagnostics(EditorTab tab) {
    final source = tab.controller.text;
    if (_diagnosticsCacheTabId == tab.id &&
        _diagnosticsCacheLanguage == tab.language &&
        _diagnosticsCacheSource == source) {
      return List<String>.of(_diagnosticsCache);
    }
    final result = _computeDiagnostics(tab, source);
    _diagnosticsCacheTabId = tab.id;
    _diagnosticsCacheLanguage = tab.language;
    _diagnosticsCacheSource = source;
    _diagnosticsCache = result;
    return List<String>.of(result);
  }

  List<String> _computeDiagnostics(EditorTab tab, String source) {
    final diagnostics = <String>[];
    try {
      switch (tab.language) {
        case 'JSON':
          jsonDecode(source);
          break;
        case 'XML':
          XmlDocument.parse(source);
          break;
        case 'YAML':
          loadYaml(source);
          break;
      }
    } catch (error) {
      final message = error.toString().replaceFirst(RegExp(r'^.*?:\s*'), '');
      diagnostics.add('${tab.language}: $message');
    }

    // Structural checks complement the real JSON/XML/YAML parsers. They are
    // deliberately labelled as lightweight editor diagnostics, not compiler
    // errors or a substitute for a language analyzer.
    diagnostics.addAll(
      EditorSyntaxDiagnostics.analyze(source, tab.language)
          .map((diagnostic) => '${tab.language}: $diagnostic'),
    );
    return diagnostics;
  }

  void _showTerminalPanel() {
    if (_terminalFullScreen) return;
    setState(() {
      _bottomPanelVisible = true;
      _bottomPanelTab = 2;
      _editorFullScreen = false;
      _terminalFullScreen = true;
    });
    _saveEditorPreferences();

    Navigator.of(context)
        .push(
          _DarkPageRoute<void>(
            builder: (_) => TerminalFullScreenScreen(
              files: safFiles,
              projectUri: projectUri,
              projectName: projectName,
              onOpenFile: (file, parentUri) async {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                await openProjectFile(file, parentUri, closeOverlay: false);
              },
            ),
          ),
        )
        .whenComplete(() {
          if (mounted) setState(() => _terminalFullScreen = false);
        });
  }

  Widget buildBottomPanel(EditorTab tab) {
    final diagnostics = _getCurrentDiagnostics(tab);
    final lines = tab.controller.text.isEmpty
        ? 1
        : '\n'.allMatches(tab.controller.text).length + 1;
    final characters = tab.controller.text.length;
    final isProblems = _bottomPanelTab == 0;
    final isFileInfo = _bottomPanelTab == 1;

    return Container(
      height: _bottomPanelHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF101827),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              final screenHeight = MediaQuery.of(context).size.height;
              final nextHeight = _bottomPanelHeight - details.delta.dy;
              final maxHeight = screenHeight * 0.55;
              setState(() {
                _bottomPanelHeight = nextHeight.clamp(110.0, maxHeight).toDouble();
              });
              _saveEditorPreferences();
            },
            child: SizedBox(
              height: 12,
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _bottomPanelTab = 0),
                  icon: Icon(
                    Icons.error_outline,
                    size: 16,
                    color: _bottomPanelTab == 0
                        ? const Color(0xFF38BDF8)
                        : Colors.white54,
                  ),
                  label: Text(
                    'المشكلات${diagnostics.isEmpty ? '' : ' (${diagnostics.length})'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _bottomPanelTab == 0
                          ? const Color(0xFF38BDF8)
                          : Colors.white70,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _bottomPanelTab = 1),
                  icon: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: _bottomPanelTab == 1
                        ? const Color(0xFF38BDF8)
                        : Colors.white54,
                  ),
                  label: Text(
                    'معلومات الملف',
                    style: TextStyle(
                      fontSize: 11,
                      color: _bottomPanelTab == 1
                          ? const Color(0xFF38BDF8)
                          : Colors.white70,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showTerminalPanel,
                  icon: Icon(
                    Icons.terminal,
                    size: 16,
                    color: _bottomPanelTab == 2
                        ? const Color(0xFF38BDF8)
                        : Colors.white54,
                  ),
                  label: Text(
                    'الطرفية',
                    style: TextStyle(
                      fontSize: 11,
                      color: _bottomPanelTab == 2
                          ? const Color(0xFF38BDF8)
                          : Colors.white70,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'إغلاق اللوحة',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _bottomPanelVisible = false);
                    _saveEditorPreferences();
                  },
                  icon: const Icon(Icons.close, size: 17),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF263449)),
          Expanded(
            child: isProblems
                ? diagnostics.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد أخطاء تحقق معروفة لهذا النوع من الملفات',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        itemCount: diagnostics.length,
                        itemBuilder: (context, index) {
                          final diagnostic = diagnostics[index];
                          final location = RegExp(
                            r'السطر\s+(\d+)،\s*العمود\s+(\d+)',
                          ).firstMatch(diagnostic);
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orangeAccent,
                              size: 18,
                            ),
                            title: Text(
                              diagnostic,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9AABC0),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: location == null
                                ? null
                                : const Icon(
                                    Icons.my_location_outlined,
                                    size: 15,
                                    color: Color(0xFF38BDF8),
                                  ),
                            onTap: location == null
                                ? null
                                : () {
                                    final offset =
                                        EditorDiagnosticNavigation.offsetForLineColumn(
                                      tab.controller.text,
                                      int.parse(location.group(1)!),
                                      int.parse(location.group(2)!),
                                    );
                                    if (offset == null) return;
                                    tab.controller.selection =
                                        TextSelection.collapsed(offset: offset);
                                    setState(() {
                                      status = 'الانتقال إلى السطر ${location.group(1)}';
                                    });
                                    _scheduleTabStateSave();
                                  },
                          );
                        },
                      )
                : isFileInfo
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 8,
                            children: [
                              _panelInfo('الملف', tab.fileName),
                              _panelInfo('اللغة', tab.language),
                              _panelInfo('الأسطر', '$lines'),
                              _panelInfo('الأحرف', '$characters'),
                              _panelInfo('الحالة', tab.isSaved ? 'محفوظ' : 'معدّل'),
                            ],
                          ),
                        ),
                      )
                    : BishoTerminalPanel(
                        files: safFiles,
                        projectUri: projectUri,
                        projectName: projectName,
                        onOpenFile: (file, parentUri) => openProjectFile(
                          file,
                          parentUri,
                          closeOverlay: false,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _panelInfo(String label, String value) {
    return Text(
      '$label: $value',
      style: const TextStyle(fontSize: 11, color: Colors.white70),
    );
  }

  void changeEditorFontSize(double delta) {
    setState(() {
      _editorFontSize = (_editorFontSize + delta).clamp(10.0, 24.0).toDouble();
      status = 'حجم الخط: ${_editorFontSize.toStringAsFixed(0)}';
    });
    _saveEditorPreferences();
  }

  Future<void> showCodeCompletions() async {
    final tab = activeTab;
    final controller = tab.controller;
    final source = controller.text;
    final selection = controller.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, source.length).toInt()
        : source.length;
    final beforeCursor = source.substring(0, cursor);
    final match = RegExp(r'[A-Za-z_][A-Za-z0-9_]*$').firstMatch(beforeCursor);
    final memberMatch = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)?$',
    ).firstMatch(beforeCursor);
    final prefix = memberMatch?.group(2) ?? match?.group(0) ?? '';
    final contextual = memberMatch == null
        ? const <String>[]
        : EditorCompletionEngine.contextualCandidates(
            receiver: memberMatch.group(1) ?? '',
            language: tab.language,
          );

    final Map<String, List<String>> completions = {
      'Dart': [
        'void main() {\n  \n}',
        'print()',
        'debugPrint()',
        'final ',
        'const ',
        'late final ',
        'class ',
        'abstract class ',
        'Future<void> ',
        'async',
        'await ',
        'try {\n  \n} catch (error, stackTrace) {\n  debugPrint(error.toString());\n}',
        'if (mounted) {\n  setState(() {\n    \n  });\n}',
        'Widget build(BuildContext context) {\n  return const SizedBox.shrink();\n}',
        'StatelessWidget',
        'StatefulWidget',
        'ListView.builder(',
        'FutureBuilder<',
        'StreamBuilder<',
        'for (var i = 0; i < items.length; i++) {\n  \n}',
      ],
      'JavaScript': [
        'console.log()',
        'const ',
        'let ',
        'function ',
        'async function ',
        'if () {\n  \n}',
        'for (let i = 0; i < ; i++) {\n  \n}',
        'try {\n  \n} catch (error) {\n  console.error(error);\n}',
      ],
      'TypeScript': [
        'console.log()',
        'const ',
        'let ',
        'interface ',
        'type ',
        'function ',
        'async function ',
        'Promise<void>',
      ],
      'Python': [
        'print()',
        'def ',
        'class ',
        'if __name__ == "__main__":\n    ',
        'for item in items:\n    ',
        'with open("file.txt", "r", encoding="utf-8") as file:\n    content = file.read()',
        'try:\n    \nexcept Exception as error:\n    print(error)',
        'import ',
      ],
      'HTML': [
        '<!DOCTYPE html>\n<html lang="ar">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title></title>\n</head>\n<body>\n  \n</body>\n</html>',
        '<div></div>',
        '<p></p>',
        '<script>\n\n</script>',
        '<style>\n\n</style>',
      ],
      'CSS': [
        'display: flex;',
        'display: grid;',
        'margin: ;',
        'padding: ;',
        'color: ;',
        '@media (max-width: 600px) {\n  \n}',
      ],
      'SQL': [
        'SELECT * FROM ;',
        'SELECT  FROM  WHERE ;',
        'INSERT INTO  () VALUES ();',
        'UPDATE  SET  =  WHERE ;',
        'CREATE TABLE  (\n  id INTEGER PRIMARY KEY\n);',
      ],
      'Java': [
        'public static void main(String[] args) {\n    \n}',
        'System.out.println()',
        'private final ',
        'try {\n    \n} catch (Exception error) {\n    error.printStackTrace();\n}',
        '@Override',
        'class ',
      ],
      'Kotlin': [
        'fun main() {\n    \n}',
        'fun ',
        'suspend fun ',
        'data class ',
        'sealed class ',
        'val ',
        'var ',
        'when (value) {\n    else -> {}\n}',
        'try {\n    \n} catch (error: Exception) {\n    error.printStackTrace()\n}',
      ],
      'C++': [
        '#include <iostream>',
        'int main() {\n    std::cout << "Hello" << std::endl;\n    return 0;\n}',
        'std::vector<int> ',
        'std::string ',
        'for (int i = 0; i < ; ++i) {\n    \n}',
        'class ',
      ],
      'Bash': [
        '#!/usr/bin/env bash',
        'set -euo pipefail',
        'if [[  ]]; then\n  \nfi',
        'for item in "\${items[@]}"; do\n  \n done',
        'function () {\n  \n}',
      ],
      'Markdown': ['# ', '## ', '- ', '1. ', '```\n\n```', '> '],
      'YAML': ['name: ', 'version: ', 'dependencies:\n  ', 'scripts:\n  '],
      'JSON': ['{\n  "": ""\n}', '[\n  \n]'],
      'XML': ['<?xml version="1.0" encoding="UTF-8"?>\n<root>\n</root>', '<root></root>'],
    };

    final candidates = completions[tab.language] ??
        <String>['// TODO: ', 'if () {\n  \n}', 'class ', 'function '];
    final options = EditorCompletionEngine.rank(
      language: tab.language,
      prefix: prefix,
      snippets: [
        ...contextual,
        ...candidates,
        ...EditorCompletionEngine.identifiersIn(
          source,
          language: tab.language,
        ),
      ],
      maximumResults: 50,
    );

    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إكمال تلقائي — ${tab.language}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: options.isEmpty
              ? const Center(child: Text('لا توجد اقتراحات مطابقة'))
              : ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.code, size: 18),
                    title: Text(
                      options[index].replaceAll('\n', ' ↵ '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                    ),
                    onTap: () => Navigator.pop(dialogContext, options[index]),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;
    // Do not apply a stale completion if the document changed while the
    // suggestion dialog was open. This preserves newer user edits.
    if (controller.text != source) {
      setState(() {
        status = 'تغير محتوى المحرر أثناء عرض الاقتراح؛ لم يتم إدراج الإكمال.';
      });
      return;
    }
    final currentSelection = controller.selection;
    final hasSelection =
        currentSelection.isValid && !currentSelection.isCollapsed;
    final replaceStart = hasSelection
        ? currentSelection.start.clamp(0, source.length).toInt()
        : (match?.start ?? cursor);
    final replaceEnd = hasSelection
        ? currentSelection.end.clamp(0, source.length).toInt()
        : cursor;
    final updated = source.replaceRange(replaceStart, replaceEnd, chosen);
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: replaceStart + chosen.length),
    );
    setState(() {
      tab.isSaved = false;
      status = 'تم إدراج الإكمال';
    });
    _scheduleTabStateSave();
  }

  Future<void> copyCode() async {
    final controller = activeTab.controller;
    final selection = controller.selection;
    final text = selection.isValid && !selection.isCollapsed
        ? controller.text.substring(selection.start, selection.end)
        : controller.text;
    await Clipboard.setData(ClipboardData(text: text));
    showMessage(selection.isValid && !selection.isCollapsed
        ? 'تم نسخ النص المحدد'
        : 'تم نسخ الكود كاملاً');
  }

  void openFlutterPreview() {
    Navigator.push(
      context,
      _DarkPageRoute(
        builder: (_) => FlutterPreviewScreen(
          projectName: projectName,
          projectUri: projectUri,
          safFiles: safFiles,
          onPickProject: openProjectFolder,
          projectUriProvider: () => projectUri,
          projectNameProvider: () => projectName,
        ),
      ),
    );
  }

  Future<void> openLanguagePreview() async {
    final tab = activeTab;
    final engine = LanguageEngineManager.engineForFile(tab.fileName);

    switch (engine) {
      case LanguageEngine.webProject:
        // إذا فتح المستخدم ملف HTML منفرداً، نطلب منه اختيار مجلد المشروع
        // مرة واحدة ثم نتابع المعاينة تلقائياً بدلاً من إيقافه برسالة فقط.
        if (projectUri == null || projectUri!.isEmpty) {
          showMessage('اختر مجلد المشروع الذي يحتوي ملف HTML وموارده');
          await openProjectFolder();
          if (!mounted || projectUri == null || projectUri!.isEmpty) return;
        }

        final htmlUri = tab.fileUri;
        if (htmlUri == null || htmlUri.isEmpty) {
          showMessage(
            'هذا الملف غير مرتبط بموقع داخل المشروع. افتحه من مستكشف المشروع أو احفظه داخله أولاً.',
          );
          return;
        }

        // تحقق من أن ملف HTML موجود فعلاً داخل جذر المشروع المختار.
        try {
          final rootItem = await safFiles.getItem(projectUri!);
          if (rootItem == null || !rootItem.isDir) {
            showMessage('تعذر الوصول إلى مجلد المشروع؛ اختره مرة أخرى');
            return;
          }
          final projectTree = await collectSubtree(rootItem);
          final fileBelongsToProject = projectTree.any(
            (entry) => entry.uri == htmlUri && !entry.isDir,
          );
          if (!fileBelongsToProject) {
            showMessage(
              'ملف HTML ليس داخل مجلد المشروع المختار. اختر المجلد الأب الصحيح.',
            );
            return;
          }
        } catch (error) {
          showMessage('تعذر فحص ملفات المشروع: $error');
          return;
        }

        if (!mounted) return;
        await Navigator.push(
          context,
          _DarkPageRoute(
            builder: (_) => HtmlPreviewScreen(
              htmlCode: tab.controller.text,
              projectUri: projectUri,
              htmlFileUri: htmlUri,
            ),
          ),
        );
        return;

      case LanguageEngine.webCode:
        final mode =
            LanguageEngineManager.webModeForFile(tab.fileName);

        if (mode == null) {
          showMessage('نوع ملف الويب غير مدعوم');
          return;
        }

        await Navigator.push(
          context,
          _DarkPageRoute(
            builder: (_) => WebCodeRunnerScreen(
              code: tab.controller.text,
              fileName: tab.fileName,
              mode: mode,
            ),
          ),
        );
        return;

      case LanguageEngine.jsonViewer:
        await Navigator.push(
          context,
          _DarkPageRoute(
            builder: (_) => WebCodeRunnerScreen(
              code: tab.controller.text,
              fileName: tab.fileName,
              mode: 'json',
            ),
          ),
        );
        return;

      case LanguageEngine.unsupported:
        _showExecutionCapabilityDialog(tab.fileName);
        return;
    }
  }

  void _showExecutionCapabilityDialog(String fileName) {
    final capability = LanguageEngineManager.capabilitiesForFile(fileName);
    final language = capability?.language ?? 'هذه اللغة';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          const Expanded(child: Text('تشغيل هذا النوع من الملفات')),
        ]),
        content: Text(
          'يدعم Bisho IDE تحرير $language وتلوين الكود، لكن لا يحتوي حالياً '
          'على مترجم أو مفسّر محلي لهذا النوع.\n\n'
          'يمكنك متابعة التحرير والحفظ واستخدام أدوات الفحص المتاحة. '
          'لن يبدأ التطبيق عملية تشغيل وهمية أو يعرض نتيجة غير حقيقية.',
          style: const TextStyle(height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('حسناً'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openDiagnosticsPanel();
            },
            icon: const Icon(Icons.rule_rounded),
            label: const Text('فحص الكود'),
          ),
        ],
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget buildExplorerNode(String directoryUri, int depth) {
    return FutureBuilder<List<SafDocumentFile>>(
      key: ValueKey('$_explorerRevision-$directoryUri'),
      future: safFiles.listDirectory(directoryUri),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return const ListTile(
            dense: true,
            title: Text('تعذر قراءة المجلد'),
          );
        }

        final items =
            List<SafDocumentFile>.from(snapshot.data ?? []);

        final filter = _explorerFilter.trim().toLowerCase();
        const explorerTypeExtensions = <String, Set<String>>{
          'code': {'dart', 'py', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cpp', 'hpp', 'go', 'rs', 'php', 'sh', 'bash'},
          'config': {'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'properties', 'gradle'},
          'web': {'html', 'htm', 'css', 'scss', 'sass', 'md', 'markdown'},
          'media': {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'mp3', 'wav', 'mp4', 'webm'},
        };
        items.removeWhere((item) {
          if (item.isDir) return false;
          if (filter.isNotEmpty && !item.name.toLowerCase().contains(filter)) return true;
          final allowed = explorerTypeExtensions[_explorerTypeFilter];
          if (allowed == null) return false;
          final dot = item.name.lastIndexOf('.');
          final extension = dot < 0 ? '' : item.name.substring(dot + 1).toLowerCase();
          return !allowed.contains(extension);
        });

        items.sort((a, b) {
          if (a.isDir && !b.isDir) return -1;
          if (!a.isDir && b.isDir) return 1;

          return a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              );
        });

        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              filter.isEmpty ? 'المجلد فارغ' : 'لا توجد عناصر تطابق البحث',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((entity) {
            if (entity.isDir) {
              final isSelectedDirectory =
                  selectedDirectoryUri == entity.uri;

              return Padding(
                padding: EdgeInsets.only(right: depth * 5.0),
                child: ExpansionTile(
                  key: PageStorageKey<String>(entity.uri),
                  dense: true,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                  ),
                  leading: Icon(
                    isSelectedDirectory
                        ? Icons.folder_special
                        : Icons.folder,
                    color: isSelectedDirectory
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFFFBBF24),
                    size: 20,
                  ),
                  title: Text(
                    entity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelectedDirectory
                          ? const Color(0xFF38BDF8)
                          : null,
                      fontWeight: isSelectedDirectory
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) {
                      if (value == 'select') {
                        selectCreationDirectory(
                          entity.uri,
                          entity.name,
                        );
                      }

                      if (value == 'rename') {
                        renameEntity(entity);
                      }

                      if (value == 'delete') {
                        deleteEntity(entity);
                      }
                      if (value == 'copy') {
                        copyOrMoveEntity(entity, move: false);
                      }
                      if (value == 'move') {
                        copyOrMoveEntity(entity, move: true);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'select',
                        child: Row(
                          children: [
                            Icon(
                              Icons.drive_file_move,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text('تعيين كمجلد عمل'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'copy', child: Text('نسخ إلى مجلد…')),
                      const PopupMenuItem(value: 'move', child: Text('نقل إلى مجلد…')),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('إعادة تسمية'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف'),
                      ),
                    ],
                  ),
                  children: [
                    buildExplorerNode(entity.uri, depth + 1),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(right: depth * 5.0),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                leading: LanguageBrandBadge(
                  language: LanguageIdentity.fromFileName(entity.name).name,
                  size: 25,
                ),
                title: Text(
                  entity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => openProjectFile(entity, directoryUri),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (value) {
                    if (value == 'rename') {
                      renameEntity(entity);
                    }

                    if (value == 'delete') {
                      deleteEntity(entity);
                    }
                    if (value == 'copy') {
                      copyOrMoveEntity(entity, move: false);
                    }
                    if (value == 'move') {
                      copyOrMoveEntity(entity, move: true);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'copy', child: Text('نسخ إلى مجلد…')),
                    PopupMenuItem(value: 'move', child: Text('نقل إلى مجلد…')),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('إعادة تسمية'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف'),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget buildExplorer() {
    return Container(
      width: 300,
      color: const Color(0xFF0F1A2A),
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF16263B),
              border: Border(bottom: BorderSide(color: Color(0xFF30445E))),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_copy_rounded, color: Color(0xFF38BDF8), size: 19),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'مستكشف الملفات',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: createProjectFile,
                  icon: const Icon(Icons.note_add, size: 19),
                  tooltip: 'ملف جديد',
                ),
                IconButton(
                  onPressed: createProjectFolder,
                  icon: const Icon(Icons.create_new_folder, size: 19),
                  tooltip: 'مجلد جديد',
                ),
                IconButton(
                  onPressed: refreshExplorer,
                  icon: const Icon(Icons.refresh, size: 19),
                  tooltip: 'تحديث المستكشف',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (projectUri != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 5),
              child: TextField(
                controller: _explorerFilterController,
                onChanged: (value) => setState(() => _explorerFilter = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'تصفية الملفات والمجلدات',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _explorerFilter.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح التصفية',
                          icon: const Icon(Icons.close, size: 17),
                          onPressed: () {
                            _explorerFilterController.clear();
                            setState(() => _explorerFilter = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          if (projectUri != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: DropdownButtonFormField<String>(
                initialValue: _explorerTypeFilter,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'نوع الملفات',
                  prefixIcon: Icon(Icons.filter_alt_outlined, size: 18),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('كل الملفات')),
                  DropdownMenuItem(value: 'code', child: Text('ملفات البرمجة')),
                  DropdownMenuItem(value: 'config', child: Text('ملفات الإعدادات')),
                  DropdownMenuItem(value: 'web', child: Text('الويب والتوثيق')),
                  DropdownMenuItem(value: 'media', child: Text('الصور والوسائط')),
                ],
                onChanged: (value) => setState(() => _explorerTypeFilter = value ?? 'all'),
              ),
            ),
          if (projectUri == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.folder_open,
                        size: 38,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'لم يتم فتح مشروع',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: openProjectFolder,
                        child: const Text('فتح مجلد'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.folder,
                      color: Color(0xFFFBBF24),
                    ),
                    title: Text(
                      projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: openProjectFolder,
                      icon: const Icon(Icons.folder_open, size: 18),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: selectedDirectoryUri != null
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFF334155),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedDirectoryUri != null
                              ? Icons.folder_special
                              : Icons.home_work,
                          size: 15,
                          color: const Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'العمل: $creationDirectoryName',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        if (selectedDirectoryUri != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: 'العودة إلى جذر المشروع',
                            onPressed: resetCreationDirectory,
                            icon: const Icon(
                              Icons.home,
                              size: 17,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: buildExplorerNode(projectUri!, 0),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildTabBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF0C1727),
        border: Border(bottom: BorderSide(color: Color(0xFF30445E))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final selected = index == activeIndex;

                return InkWell(
                  onTap: () => selectTab(index),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 100,
                      maxWidth: 180,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF182A40)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF3B7198)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        LanguageBrandBadge(
                          language: LanguageIdentity.fromFileName(tab.fileName).name,
                          size: 20,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            tab.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? const Color(0xFFE6F4FF) : const Color(0xFF9AABC0),
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (!tab.isSaved)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: Colors.amber,
                            ),
                          ),
                        GestureDetector(
                          onTap: () => closeTab(index),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            onPressed: createNewTab,
            icon: const Icon(
              Icons.add,
              color: Color(0xFF38BDF8),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditorFullScreen() {
    if (_editorFullScreen || tabs.isEmpty) return;

    // Remove the embedded CodeField first. A CodeController should not be
    // attached to two CodeFields at the same time while the route animates.
    setState(() => _editorFullScreen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(
            _DarkPageRoute<void>(
              builder: (_) => EditorFullScreenScreen(
                tab: activeTab,
                fontSize: _editorFontSize,
                onSave: saveCurrentToDisk,
                onFontSizeChange: changeEditorFontSize,
                onShowCompletions: showCodeCompletions,
                onSearch: (replaceMode) =>
                    searchCode(startInReplaceMode: replaceMode),
                onPreview: openLanguagePreview,
                onFlutterPreview: openFlutterPreview,
              ),
            ),
          )
          .whenComplete(() {
            if (mounted) setState(() => _editorFullScreen = false);
          });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _explorerFilterController.dispose();
    _githubService.close();
    _packageCatalog.close();
    _isDisposing = true;
    _tabStateSaveTimer?.cancel();
    // Capture the final editor state before releasing the controllers.
    saveTabStateSilently();
    for (final tab in tabs) {
      tab.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                isRestoring ? 'جاري استعادة مساحة العمل...' : 'جاري تجهيز المحرر...',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (_editorFullScreen) {
      // The actual editor is displayed by EditorFullScreenScreen on its own
      // route. Keep this route lightweight while it is underneath.
      return const Scaffold(
        backgroundColor: Color(0xFF080D19),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tab = activeTab;
    final selection = tab.controller.selection;
    final cursorOffset = selection.isValid
        ? selection.extentOffset.clamp(0, tab.controller.text.length).toInt()
        : tab.controller.text.length;
    final cursorPosition = _cursorLineColumn(tab.controller.text, cursorOffset);
    final cursorLine = cursorPosition.$1;
    final cursorColumn = cursorPosition.$2;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmApplicationExit();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
        drawer: _editorFullScreen || !explorerVisible
            ? null
            : Drawer(
                width: 320,
                backgroundColor: const Color(0xFF111827),
                child: Theme(
                  data: BishoTheme.darkTheme,
                  child: SafeArea(child: buildExplorer()),
                ),
              ),
        appBar: _editorFullScreen ? null : AppBar(
          backgroundColor: const Color(0xFF101B2D),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 14,
          shape: const Border(
            bottom: BorderSide(color: Color(0xFF26374E), width: 0.8),
          ),
          title: const Row(
            children: [
              Icon(Icons.code_rounded, color: Color(0xFF38BDF8), size: 25),
              SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Bisho IDE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  SizedBox(height: 1),
                  Text('بيئة التطوير', style: TextStyle(color: Color(0xFF91A4BE), fontSize: 9, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: searchCode,
              icon: const Icon(Icons.search_rounded),
              tooltip: 'بحث في المشروع والكود',
            ),
            IconButton(
              onPressed: _openCommandPalette,
              icon: const Icon(Icons.keyboard_command_key_rounded, color: Color(0xFF38BDF8)),
              tooltip: 'لوحة الأوامر',
            ),
            IconButton(
              onPressed: saveCurrentToDisk,
              icon: const Icon(Icons.save_rounded),
              tooltip: 'حفظ الملف',
            ),
            IconButton(
              onPressed: _showTerminalPanel,
              icon: const Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8)),
              tooltip: 'فتح الطرفية',
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد من الأدوات',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'new') createNewTab();
                if (value == 'new_project') createNewProject();
                if (value == 'open') openFile();
                if (value == 'folder') openProjectFolder();
                if (value == 'projects') showProjectManager();
                if (value == 'export') exportFile();
                if (value == 'export_project') exportProjectArchive();
                if (value == 'import_zip') importProjectArchive();
                if (value == 'search') searchCode();
                if (value == 'copy') copyCode();
                if (value == 'saveall') saveAllTabs();
                if (value == 'terminal') _showTerminalPanel();
                if (value == 'complete') showCodeCompletions();
                if (value == 'fullscreen') _openEditorFullScreen();
                if (value == 'theme') BishoThemeController.toggle();
                if (value == 'exit') _confirmApplicationExit();
              },
              itemBuilder: (context) => [
                _bishoMenuItem('new', Icons.note_add_rounded, 'ملف جديد'),
                _bishoMenuItem('new_project', Icons.create_new_folder_rounded, 'إنشاء مشروع جديد'),
                _bishoMenuItem('open', Icons.file_open_rounded, 'فتح ملف'),
                _bishoMenuItem('folder', Icons.folder_open_rounded, 'فتح مجلد مشروع'),
                _bishoMenuItem('projects', Icons.workspaces_rounded, 'مدير المشاريع الذكي'),
                const PopupMenuDivider(),
                _bishoMenuItem('export', Icons.download_rounded, 'تصدير الملف'),
                _bishoMenuItem('export_project', Icons.archive_rounded, 'تصدير المشروع ZIP كاملاً'),
                _bishoMenuItem('import_zip', Icons.unarchive_rounded, 'استيراد مشروع ZIP'),
                const PopupMenuDivider(),
                _bishoMenuItem('search', Icons.search_rounded, 'بحث'),
                _bishoMenuItem('copy', Icons.copy_rounded, 'نسخ الكود'),
                _bishoMenuItem('complete', Icons.auto_awesome_rounded, 'الإكمال التلقائي'),
                _bishoMenuItem('saveall', Icons.save_rounded, 'حفظ جميع الملفات'),
                _bishoMenuItem('terminal', Icons.terminal_rounded, 'فتح الطرفية'),
                _bishoMenuItem('fullscreen', Icons.fullscreen_rounded, 'فتح المحرر في شاشة كاملة'),
                _bishoMenuItem('theme', Icons.palette_outlined, 'تبديل المظهر'),
                const PopupMenuDivider(),
                _bishoMenuItem('exit', Icons.exit_to_app_rounded, 'الخروج من التطبيق', color: Colors.orangeAccent),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            if (_editorFullScreen)
              Container(
                height: 48,
                color: const Color(0xFF151C30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _editorFullScreen = false),
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: 'العودة إلى واجهة IDE',
                    ),
                    Expanded(
                      child: Text(
                        tab.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: saveCurrentToDisk,
                      icon: const Icon(Icons.save),
                      tooltip: 'حفظ الملف',
                    ),
                  ],
                ),
              ),
            if (!_editorFullScreen) ...[
            Theme(data: BishoTheme.darkTheme, child: buildTabBar()),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 16, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButton<String>(
                    borderRadius: BorderRadius.circular(12),
                    isDense: true,
                    value: tab.language,
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    underline: const SizedBox(),
                    items: languages.keys.map((language) {
                      return DropdownMenuItem<String>(
                        value: language,
                        child: Text(language),
                      );
                    }).toList(),
                    onChanged: changeLanguage,
                  ),
                ],
              ),
            ),

            Expanded(
              child: Theme(
                data: BishoTheme.darkTheme,
                child: _buildToolsDashboard(tab),
              ),
            ),
            if (!_editorFullScreen && _bottomPanelVisible)
              Theme(data: BishoTheme.darkTheme, child: buildBottomPanel(tab)),
            if (!_editorFullScreen)
              Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF101B2D),
                border: Border(top: BorderSide(color: Color(0xFF26374E))),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: tab.isSaved ? Colors.green : Colors.amber,
                    size: 9,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  Text(
                    'Ln $cursorLine, Col $cursorColumn',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tab.language,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tab.isSaved ? 'محفوظ' : 'غير محفوظ',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildToolsDashboard(EditorTab tab) {
    final selection = tab.controller.selection;
    final cursorOffset = selection.isValid
        ? selection.extentOffset.clamp(0, tab.controller.text.length).toInt()
        : tab.controller.text.length;
    final cursorPosition = _cursorLineColumn(tab.controller.text, cursorOffset);
    const cyan = Color(0xFF38BDF8);
    const blue = Color(0xFF60A5FA);
    const violet = Color(0xFFA78BFA);
    const green = Color(0xFF34D399);
    const amber = Color(0xFFFBBF24);
    const red = Color(0xFFFB7185);

    // Keep every existing command reachable; this is a presentation-only
    // regrouping. Action callbacks and their underlying services are unchanged.
    final projectActions = <_DashboardAction>[
      _DashboardAction(Icons.create_new_folder_rounded, 'إنشاء مشروع', createNewProject, cyan),
      _DashboardAction(Icons.folder_open_rounded, 'فتح مجلد مشروع', openProjectFolder, cyan),
      _DashboardAction(Icons.workspaces_rounded, 'مدير المشاريع الذكي', showProjectManager, violet),
      _DashboardAction(Icons.account_tree_rounded, 'GitHub وربط المستودع', _openGitHubManager, green),
      _DashboardAction(Icons.drive_folder_upload_rounded, 'استيراد مشروع', importExistingProject, green),
      _DashboardAction(Icons.note_add_rounded, 'ملف جديد', createNewTab, cyan),
      _DashboardAction(Icons.file_open_rounded, 'فتح ملف', openFile, cyan),
      _DashboardAction(Icons.save_rounded, 'حفظ الملف', saveCurrentToDisk, cyan),
      _DashboardAction(Icons.save_as_rounded, 'حفظ جميع الملفات', saveAllTabs, green),
      _DashboardAction(Icons.download_rounded, 'تصدير ملف', exportFile, blue),
      _DashboardAction(Icons.archive_rounded, 'تصدير المشروع ZIP', exportProjectArchive, blue),
      _DashboardAction(Icons.unarchive_rounded, 'استيراد مشروع ZIP', importProjectArchive, green),
      _DashboardAction(Icons.backup_rounded, 'إنشاء نسخة احتياطية', exportProjectBackup, green),
      _DashboardAction(Icons.settings_backup_restore_rounded, 'استعادة نسخة احتياطية', restoreProjectBackup, green),
      _DashboardAction(Icons.history_rounded, 'سجل النسخ الاحتياطية', manageProjectBackups, green),
    ];

    final buildActions = <_DashboardAction>[
      _DashboardAction(Icons.build_circle_rounded, 'مركز البناء والمحرك', openFlutterPreview, blue),
    ];

    final editingActions = <_DashboardAction>[
      _DashboardAction(Icons.search_rounded, 'البحث في الكود', searchCode, cyan),
      _DashboardAction(Icons.vertical_split_rounded, 'تقسيم المحرر', _openSplitEditor, violet),
      _DashboardAction(Icons.find_replace_rounded, 'البحث والاستبدال', () => searchCode(startInReplaceMode: true), violet),
      _DashboardAction(Icons.manage_search_rounded, 'بحث متقدم (Regex)', _openAdvancedSearch, cyan),
      _DashboardAction(Icons.undo_rounded, 'تراجع', undoCodeEdit, red),
      _DashboardAction(Icons.redo_rounded, 'إعادة', redoCodeEdit, green),
      _DashboardAction(Icons.auto_awesome_rounded, 'الإكمال التلقائي', showCodeCompletions, violet),
      _DashboardAction(Icons.copy_all_rounded, 'تكرار الأسطر', duplicateSelectedLines, cyan),
      _DashboardAction(Icons.arrow_upward_rounded, 'نقل السطر لأعلى', moveCurrentLineUp, cyan),
      _DashboardAction(Icons.arrow_downward_rounded, 'نقل السطر لأسفل', moveCurrentLineDown, cyan),
      _DashboardAction(Icons.comment_rounded, 'تعليق أو إلغاء التعليق', toggleSelectedLineComments, green),
      _DashboardAction(Icons.compare_arrows_rounded, 'الانتقال للقوس المطابق', jumpToMatchingBracket, cyan),
      _DashboardAction(Icons.copy_rounded, 'نسخ الكود', copyCode, blue),
      _DashboardAction(Icons.text_increase_rounded, 'تكبير خط المحرر', () => changeEditorFontSize(1), cyan),
      _DashboardAction(Icons.text_decrease_rounded, 'تصغير خط المحرر', () => changeEditorFontSize(-1), cyan),
      _DashboardAction(Icons.difference_rounded, 'مقارنة النص', _openTextDiffDialog, violet),
    ];

    final qualityActions = <_DashboardAction>[
      _DashboardAction(Icons.auto_fix_high_rounded, 'مساعد إصلاح الأخطاء', _openDiagnosticsPanel, amber),
      _DashboardAction(Icons.auto_fix_high_rounded, 'إصلاحات مقترحة بمعاينة', _openFixAssistant, amber),
      _DashboardAction(Icons.format_align_left_rounded, 'تنسيق الكود', _openFormatPreview, cyan),
      _DashboardAction(Icons.restore_rounded, 'سجل إصدارات الملف', _openVersionHistory, green),
      _DashboardAction(Icons.health_and_safety_rounded, 'فحص جودة المشروع', _openProjectInsightsPanel, green),
      _DashboardAction(Icons.extension_rounded, 'الإضافات والأدوات المدمجة', _showPluginsHub, blue),
      _DashboardAction(Icons.account_tree_rounded, 'مستكشف شجرة Widgets', _openWidgetTreeInspector, cyan),
      _DashboardAction(Icons.inventory_2_rounded, 'مدير حزم Flutter وDart', _openFlutterPackageManager, blue),
      _DashboardAction(Icons.smart_toy_rounded, 'مساعد الكود المحلي', _openLocalCodeAssistant, violet),
      _DashboardAction(Icons.code_rounded, 'اللغات والقدرات المدعومة', _showLanguageCapabilities, cyan),
      _DashboardAction(Icons.info_outline_rounded, 'معلومات المحرر', _showEditorInfoDialog, blue),
    ];

    final preferenceActions = <_DashboardAction>[
      _DashboardAction(Icons.tune_rounded, 'إعدادات مساحة العمل', _showWorkspaceSettings, blue),
      _DashboardAction(Icons.palette_rounded, 'تبديل المظهر الفاتح والداكن', _showDashboardThemeInfo, violet),
      _DashboardAction(Icons.bug_report_outlined, 'لوحة المشكلات', _openDiagnosticsPanel, amber),
    ];

    final allActions = <_DashboardAction>[
      ...projectActions,
      ...buildActions,
      ...editingActions,
      ...qualityActions,
      ...preferenceActions,
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101D32), Color(0xFF0B1220), Color(0xFF080E19)],
          stops: [0, .38, 1],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        children: [
          _dashboardFileStrip(tab),
          if (_splitTabId != null) ...[
            const SizedBox(height: 12),
            _buildSplitEditorPanel(),
          ],
          const SizedBox(height: 13),
          _dashboardHero(tab),
          const SizedBox(height: 16),
          _dashboardPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cyan.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.code_rounded, color: cyan, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('مساحة العمل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        projectName == 'لا يوجد مشروع' ? 'ابدأ مشروعاً جديداً أو افتح ملفاتك' : projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9BAFCB)),
                      ),
                    ],
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: tab.isSaved ? green.withValues(alpha: .12) : amber.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 7, color: tab.isSaved ? green : amber),
                      const SizedBox(width: 6),
                      Text(tab.isSaved ? 'محفوظ' : 'غير محفوظ',
                        style: TextStyle(fontSize: 10, color: tab.isSaved ? green : amber, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _dashboardProjectCard(
                    icon: Icons.folder_special_rounded,
                    title: projectName == 'لا يوجد مشروع' ? 'المشروع الحالي' : projectName,
                    subtitle: projectUri ?? 'لا يوجد مجلد مشروع مرتبط حالياً',
                    onTap: projectUri != null ? openProjectFolder : createNewProject,
                    accent: cyan,
                  )),
                ]),
                const SizedBox(height: 8),
                _workspaceMetricsPanel(),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _dashboardActionSection(
            icon: Icons.folder_copy_rounded,
            title: 'المشاريع والملفات',
            subtitle: 'إنشاء وفتح واستيراد وحفظ وتصدير ونسخ احتياطي',
            actions: projectActions,
            initiallyExpanded: true,
          ),
          const SizedBox(height: 16),
          _dashboardActionSection(
            icon: Icons.build_circle_rounded,
            title: 'البناء والمحرك المحلي والسحابي',
            subtitle: 'إدارة المحرك وفحصه وتشغيل البناء ومتابعة APK',
            actions: buildActions,
          ),
          const SizedBox(height: 16),
          _dashboardActionSection(
            icon: Icons.edit_note_rounded,
            title: 'أدوات تحرير الكود',
            subtitle: 'البحث والتعديل والتنقل والإكمال وأدوات النص',
            actions: editingActions,
          ),
          const SizedBox(height: 16),
          _dashboardActionSection(
            icon: Icons.fact_check_rounded,
            title: 'الفحص والأدوات',
            subtitle: 'تحليل الكود وجودة المشروع واللغات والإضافات',
            actions: qualityActions,
          ),
          const SizedBox(height: 16),
          _dashboardActionSection(
            icon: Icons.settings_rounded,
            title: 'التفضيلات والإعدادات',
            subtitle: 'تخصيص مساحة العمل ومظهر التطبيق',
            actions: preferenceActions,
          ),
          const SizedBox(height: 14),
          _dashboardPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dashboardSectionTitle(Icons.flash_on_rounded, 'بدء سريع'),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, constraints) {
                  final width = (constraints.maxWidth - 9) / 2;
                  final quickActions = <_DashboardAction>[
                    _DashboardAction(Icons.create_new_folder_rounded, 'مشروع جديد', createNewProject, cyan),
                    _DashboardAction(Icons.folder_open_rounded, 'فتح مشروع', openProjectFolder, green),
                    _DashboardAction(Icons.note_add_rounded, 'ملف جديد', createNewTab, blue),
                    _DashboardAction(Icons.search_rounded, 'بحث في الكود', searchCode, violet),
                  ];
                  return Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: quickActions.map((action) => SizedBox(
                      width: width,
                      child: _dashboardFeatureCard(action),
                    )).toList(),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _dashboardPanel(
            child: Row(children: [
              const Icon(Icons.insert_drive_file_outlined, color: cyan, size: 19),
              const SizedBox(width: 9),
              Expanded(child: Text(tab.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
              Text(tab.language, style: const TextStyle(color: cyan, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('Ln ${cursorPosition.$1}, Col ${cursorPosition.$2}',
                style: const TextStyle(color: Color(0xFF9BAFCB), fontSize: 10, fontFamily: 'monospace')),
            ]),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showAllDashboardTools(allActions),
            icon: const Icon(Icons.apps_rounded),
            label: const Text('عرض جميع الأدوات في قائمة واحدة'),
          ),
        ],
      ),
    );
  }

  Widget _dashboardHero(EditorTab tab) {
    const cyan = Color(0xFF38BDF8);
    const violet = Color(0xFFA78BFA);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF173D61), Color(0xFF18264B), Color(0xFF251D49)],
        ),
        border: Border.all(color: const Color(0xFF47739C).withValues(alpha: .65)),
        boxShadow: const [BoxShadow(color: Color(0x26038BCE), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.terminal_rounded, color: cyan, size: 27)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مرحباً بك في Bisho IDE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('بيئة عملك البرمجية — أنشئ، حرّر، وابنِ تطبيقاتك', maxLines: 2,
              style: TextStyle(color: Color(0xFFC5D8EF), fontSize: 11, height: 1.35)),
          ])),
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 17),
        Row(children: [
          Expanded(child: _heroMetric(Icons.folder_special_rounded, 'المشروع', projectName == 'لا يوجد مشروع' ? 'غير محدد' : projectName)),
          const SizedBox(width: 8),
          Expanded(child: _heroMetric(Icons.description_rounded, 'الملف المفتوح', tab.fileName)),
          const SizedBox(width: 8),
          Expanded(child: _heroMetric(Icons.code_rounded, 'اللغة', tab.language)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: projectUri == null ? createNewProject : openProjectFolder,
            icon: Icon(projectUri == null ? Icons.add_rounded : Icons.folder_open_rounded, size: 18),
            label: Text(projectUri == null ? 'ابدأ مشروعاً' : 'فتح المشروع'),
            style: FilledButton.styleFrom(backgroundColor: cyan, foregroundColor: const Color(0xFF06243A),
              minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 9),
          Expanded(child: OutlinedButton.icon(
            onPressed: createNewTab,
            icon: const Icon(Icons.note_add_rounded, size: 18),
            label: const Text('ملف جديد'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF7897BC)),
              minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.tips_and_updates_outlined, size: 14, color: violet),
          const SizedBox(width: 6),
          Expanded(child: Text(tab.isSaved ? 'مساحة العمل جاهزة — جميع التغييرات محفوظة' : 'لديك تغييرات غير محفوظة في الملف الحالي',
            style: TextStyle(color: tab.isSaved ? const Color(0xFFB8F5DC) : const Color(0xFFFFD58A), fontSize: 10.5))),
        ]),
      ]),
    );
  }

  Widget _heroMetric(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .16), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .09))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 13, color: const Color(0xFF8DDCFF)), const SizedBox(width: 5),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFB8CBE1), fontSize: 9)))]),
      const SizedBox(height: 5),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _dashboardActionSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<_DashboardAction> actions,
    bool initiallyExpanded = false,
  }) {
    return _dashboardPanel(
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: const Color(0xFF38BDF8).withValues(alpha: .06),
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: const Color(0xFF38BDF8), size: 20),
          ),
          title: Text(title, style: const TextStyle(
            color: Color(0xFFE5EDF7), fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 9) / 2;
              return Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final action in actions)
                    SizedBox(width: width, child: _dashboardFeatureCard(action)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _dashboardFeatureCard(_DashboardAction action) {
    return Material(
      color: const Color(0xFF17263A),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFF344B68)),
          ),
          child: Row(children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(action.icon, color: action.color, size: 19),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              action.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: const TextStyle(color: Color(0xFFE5EDF7), fontSize: 11, height: 1.28, fontWeight: FontWeight.w600),
            )),
            const Icon(Icons.chevron_left_rounded, size: 17, color: Color(0xFF71839D)),
          ]),
        ),
      ),
    );
  }

  Widget _dashboardFileStrip(EditorTab tab) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFF111D30),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFF26374E)),
    ),
    child: Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF38BDF8).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF38BDF8)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الملف النشط', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
          const SizedBox(height: 3),
          Text(tab.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFE7EFFB), fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      )),
      IconButton(
        tooltip: 'إنشاء تبويب جديد',
        onPressed: createNewTab,
        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8), size: 25),
      ),
    ]),
  );

  // ignore: unused_element
  Widget _dashboardGlowPanel({required Widget child}) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(25),
      gradient: const LinearGradient(colors: [Color(0xFF0789D7), Color(0xFF202A73), Color(0xFF8C20D8)]),
      boxShadow: [BoxShadow(color: const Color(0xFF087FEA).withValues(alpha: .22), blurRadius: 18, spreadRadius: 1)]),
    child: Container(padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: const Color(0xFF0A142A), borderRadius: BorderRadius.circular(19)),
      child: child),
  );

  // ignore: unused_element
  Widget _dashboardSquareAction(IconData icon, String label, Color color, VoidCallback onTap) =>
    Material(color: const Color(0xFF111E37), borderRadius: BorderRadius.circular(19),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(19),
        child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(19),
          border: Border.all(color: color.withValues(alpha: .42))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 31), const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ]))));

  // ignore: unused_element
  Widget _dashboardPillButton(String label, IconData icon, VoidCallback onTap) =>
    OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 19), label: Text(label),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDCE8F7),
        side: const BorderSide(color: Color(0xFF3155A7)), shape: const StadiumBorder()));

  void _showAllDashboardTools(List<_DashboardAction> actions) {
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final needle = query.trim().toLowerCase();
          final filtered = needle.isEmpty
              ? actions
              : actions
                  .where((a) => a.label.toLowerCase().contains(needle))
                  .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * .78,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        'جميع أدوات Bisho IDE',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        onChanged: (value) => setSheetState(() => query = value),
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن أداة...',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد أدوات مطابقة'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                 crossAxisSpacing: 10,
                                 mainAxisSpacing: 10,
                                 childAspectRatio: 1.65,
                              ),
                              itemBuilder: (_, index) {
                                final action = filtered[index];
                                return _dashboardToolCard(
                                  _DashboardAction(action.icon, action.label, () {
                                    Navigator.pop(sheetContext);
                                    action.onTap();
                                  }, action.color),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _workspaceMetricsPanel() {
    final metrics = WorkspaceMetrics.fromSources(
      tabs.map((tab) => tab.controller.text),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dashboardSectionTitle(Icons.insights_rounded, 'ملخص مساحة العمل'),
        const SizedBox(height: 11),
        Row(
          children: [
            _metricTile('التبويبات', metrics.fileCount.toString(), Icons.tab),
            _metricTile('الأسطر', metrics.lineCount.toString(), Icons.format_align_left),
            _metricTile('الكلمات', metrics.wordCount.toString(), Icons.text_fields),
            _metricTile('الأحرف', metrics.characterCount.toString(), Icons.notes),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'الإحصائيات محسوبة من محتوى التبويبات المفتوحة فقط',
          style: TextStyle(color: Colors.white.withValues(alpha: .48), fontSize: 10),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, IconData icon) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF38BDF8)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
      ],
    ),
  );

  Future<void> _openTextDiffDialog() async {
    final previousController = TextEditingController();
    ProjectTextDiffReport? report;
    final currentText = activeTab.controller.text;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('مقارنة النص الحالي بنسخة سابقة'),
            content: SizedBox(
              width: 620,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (report == null) ...[
                    const Text('الصق النص السابق هنا، وسيتم مقارنته بمحتوى التبويب الحالي.'),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        controller: previousController,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'النص السابق...',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ] else ...[
                    Wrap(spacing: 12, runSpacing: 6, children: [
                      Text('إضافات: ${report!.addedCount}', style: const TextStyle(color: Color(0xFF19D889))),
                      Text('حذف: ${report!.removedCount}', style: const TextStyle(color: Color(0xFFFF657A))),
                      Text('دون تغيير: ${report!.unchangedCount}', style: const TextStyle(color: Color(0xFF9BAFCB))),
                    ]),
                    if (report!.usedFallback)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('مقارنة كبيرة: عُرضت الفروقات بتقريب آمن لتقليل استهلاك الذاكرة.',
                          style: TextStyle(color: Color(0xFFFFC247), fontSize: 11)),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: const Color(0xFF080F20),
                          borderRadius: BorderRadius.circular(10)),
                        child: ListView.builder(
                          itemCount: report!.lines.length,
                          itemBuilder: (_, index) {
                            final line = report!.lines[index];
                            final added = line.kind == TextDiffKind.added;
                            final removed = line.kind == TextDiffKind.removed;
                            final prefix = added ? '+' : removed ? '-' : ' ';
                            final color = added ? const Color(0xFF19D889)
                                : removed ? const Color(0xFFFF657A) : const Color(0xFF9BAFCB);
                            return Container(
                              color: added ? const Color(0x2219D889)
                                  : removed ? const Color(0x22FF657A) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              child: Text('$prefix ${line.oldLine ?? '-'}:${line.newLine ?? '-'}  ${line.text.isEmpty ? ' ' : line.text}',
                                style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 11),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (report != null)
                TextButton(onPressed: () => setDialogState(() => report = null),
                  child: const Text('تغيير النص السابق')),
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق')),
              if (report == null)
                FilledButton.icon(
                  onPressed: () => setDialogState(() {
                    report = const ProjectTextDiff().compare(
                      previousController.text, currentText);
                  }),
                  icon: const Icon(Icons.difference_rounded),
                  label: const Text('اعرض الفروقات'),
                ),
            ],
          ),
        ),
      );
    } finally {
      previousController.dispose();
    }
  }

  void _openProjectInsightsPanel() {
    final files = <String, String>{};
    for (final tab in tabs) {
      final path = tab.fileName.replaceAll('\\\\', '/');
      if (path.isNotEmpty && !files.containsKey(path)) {
        files[path] = tab.controller.text;
      }
    }
    final report = const ProjectInsightsAnalyzer().analyze(files);
    ProjectInsightCategory? selectedCategory;

    String categoryLabel(ProjectInsightCategory category) {
      switch (category) {
        case ProjectInsightCategory.structure:
          return 'هيكل المشروع';
        case ProjectInsightCategory.imports:
          return 'الاستيرادات';
        case ProjectInsightCategory.maintenance:
          return 'الصيانة';
        case ProjectInsightCategory.security:
          return 'الأمان';
        case ProjectInsightCategory.dependencies:
          return 'الحزم';
        case ProjectInsightCategory.style:
          return 'تنسيق الكود';
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) {
          final visibleInsights = report.insights.where((issue) =>
              selectedCategory == null || issue.category == selectedCategory).toList();
          final categories = ProjectInsightCategory.values
              .where((category) => report.insights.any((issue) => issue.category == category))
              .toList();

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .78,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(children: [
                    const Icon(Icons.health_and_safety_rounded, color: Color(0xFF19D889)),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('فحص الملفات المفتوحة',
                      style: TextStyle(fontWeight: FontWeight.w800))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text('${report.filesScanned} ملف · ${report.linesScanned} سطر',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.w700)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('تحليل محلي للملفات المفتوحة فقط — لا يتم تعديل أي ملف.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    _insightCount('أخطاء', report.count(ProjectInsightSeverity.error),
                      const Color(0xFFFF647C)),
                    _insightCount('تحذيرات', report.count(ProjectInsightSeverity.warning),
                      const Color(0xFFFFC247)),
                    _insightCount('ملاحظات', report.count(ProjectInsightSeverity.info),
                      const Color(0xFF38BDF8)),
                  ])),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                  child: Row(children: [
                    const Icon(Icons.speed_rounded, size: 17, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 7),
                    const Expanded(child: Text('مؤشر جودة إرشادي للملفات المفتوحة',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))),
                    Text('${report.qualityScore}/100 · ${report.qualityLabel}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: report.qualityScore >= 90
                            ? const Color(0xFF19D889)
                            : report.qualityScore >= 75
                                ? const Color(0xFFFFC247)
                                : const Color(0xFFFF647C))),
                  ]),
                ),
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: const Text('الكل'),
                            selected: selectedCategory == null,
                            onSelected: (_) => refreshSheet(() => selectedCategory = null),
                          ),
                        ),
                        ...categories.map((category) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text(categoryLabel(category)),
                            selected: selectedCategory == category,
                            onSelected: (_) => refreshSheet(
                              () => selectedCategory = category),
                          ),
                        )),
                      ],
                    ),
                  ),
                const Divider(height: 12),
                Expanded(
                  child: visibleInsights.isEmpty
                      ? const Center(child: Text('لا توجد ملاحظات في هذا التصنيف.'))
                      : ListView.separated(
                          itemCount: visibleInsights.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final issue = visibleInsights[index];
                            final color = issue.severity == ProjectInsightSeverity.error
                                ? const Color(0xFFFF647C)
                                : issue.severity == ProjectInsightSeverity.warning
                                    ? const Color(0xFFFFC247)
                                    : const Color(0xFF38BDF8);
                            EditorTab? matchingTab;
                            for (final candidate in tabs) {
                              if (candidate.fileName.replaceAll('\\\\', '/') == issue.path) {
                                matchingTab = candidate;
                                break;
                              }
                            }
                            final targetTab = matchingTab;
                            final canNavigate = targetTab != null && issue.line > 0;

                            return ListTile(
                              dense: true,
                              leading: Icon(
                                issue.severity == ProjectInsightSeverity.error
                                    ? Icons.error_outline
                                    : issue.severity == ProjectInsightSeverity.warning
                                        ? Icons.warning_amber_rounded
                                        : Icons.info_outline,
                                color: color),
                              title: Text(issue.message,
                                style: const TextStyle(fontSize: 12)),
                              subtitle: Text(
                                issue.line > 0 ? '${issue.path}:${issue.line}' : issue.path,
                                style: const TextStyle(fontSize: 10,
                                  color: Color(0xFF94A3B8))),
                              trailing: canNavigate
                                  ? const Icon(Icons.my_location_outlined,
                                      size: 17, color: Color(0xFF38BDF8))
                                  : null,
                              onTap: canNavigate ? () {
                                                                final offset = EditorDiagnosticNavigation.offsetForLineColumn(
                                  targetTab.controller.text, issue.line, 1);
                                if (offset == null) return;
                                final tabIndex = tabs.indexOf(targetTab);
                                Navigator.pop(sheetContext);
                                setState(() {
                                  activeIndex = tabIndex;
                                  targetTab.controller.selection =
                                      TextSelection.collapsed(offset: offset);
                                });
                                _scheduleTabStateSave();
                              } : null,
                            );
                          },
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'الفحص يغطي التبويبات المفتوحة فقط. اضغط على التشخيص ذي الموقع للانتقال إليه.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  )),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _insightCount(String label, int count, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text('$count', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
      ]),
    ),
  );

  String _diagnosticAdvice(String message) {
    final value = message.toLowerCase();
    if (value.contains('قوس') || value.contains('bracket') ||
        value.contains('parenthesis') || value.contains('delimiter')) {
      return 'راجع أقواس الفتح والإغلاق بالترتيب، وتأكد أن كل قوس له نظير من النوع نفسه.';
    }
    if (value.contains('اقتباس') || value.contains('string') ||
        value.contains('quote') || value.contains('علامة تنصيص')) {
      return 'تحقق من إغلاق علامات التنصيص، ومن عدم وجود علامة اقتباس غير مهروبة داخل النص.';
    }
    if (value.contains('استيراد') || value.contains('import') ||
        value.contains('package:')) {
      return 'تحقق من اسم الحزمة ومسار الملف، وتأكد من وجود الاعتماد في pubspec.yaml عند الحاجة.';
    }
    if (value.contains('نقطة فاصلة') || value.contains('semicolon') ||
        value.contains('الفاصلة المنقوطة')) {
      return 'راجع نهاية التعليمة؛ بعض اللغات تتطلب فاصلة منقوطة وبعضها لا يتطلبها.';
    }
    if (value.contains('indent') || value.contains('مسافة بادئة') ||
        value.contains('إزاحة')) {
      return 'وحّد المسافات البادئة داخل الكتلة، وتأكد من تطابق مستوى الإزاحة مع الأقواس.';
    }
    if (value.contains('غير معروف') || value.contains('unexpected') ||
        value.contains('unexpected token')) {
      return 'راجع الرمز السابق لموضع المشكلة؛ قد يكون هناك عامل أو فاصلة أو قوس مفقود.';
    }
    return 'اقرأ رسالة الفحص وحدد أول موضع غير متوقع، ثم راجع السطر السابق والسياق المحيط قبل تعديل الملف.';
  }

  void _applyAssistantText(EditorTab tab, String value, String message) {
    if (!mounted || !tabs.contains(tab)) return;
    final caret = tab.controller.selection.baseOffset.clamp(0, value.length).toInt();
    tab.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() {
      tab.isSaved = false;
      status = message;
    });
    showMessage(message);
  }

  void _openAdvancedSearch() {
    final tab = activeTab;
    showAdvancedSearchSheet(
      context,
      fileName: tab.fileName,
      text: tab.controller.text,
      onJump: (start, end) {
        if (!mounted || !tabs.contains(tab)) return;
        final length = tab.controller.text.length;
        tab.controller.selection = TextSelection(
          baseOffset: start.clamp(0, length).toInt(),
          extentOffset: end.clamp(0, length).toInt(),
        );
      },
      onReplace: (value) =>
          _applyAssistantText(tab, value, 'تم الاستبدال؛ يمكنك التراجع'),
    );
  }

  void _openFixAssistant() {
    final tab = activeTab;
    showFixAssistantSheet(
      context,
      fileName: tab.fileName,
      source: tab.controller.text,
      language: tab.language,
      onApply: (value) =>
          _applyAssistantText(tab, value, 'تم تطبيق الإصلاحات المختارة'),
    );
  }

  void _openFormatPreview() {
    final tab = activeTab;
    showFormatPreviewSheet(
      context,
      fileName: tab.fileName,
      source: tab.controller.text,
      language: tab.language,
      onApply: (value) => _applyAssistantText(tab, value, 'تم تنسيق الكود'),
    );
  }

  Future<void> _openVersionHistory() async {
    final tab = activeTab;
    final history = await _ensureVersionHistory();
    if (!mounted) return;
    if (history == null) {
      showMessage('تعذر الوصول إلى مساحة سجل الإصدارات');
      return;
    }
    await showVersionHistorySheet(
      context,
      history: history,
      historyKey: _versionKeyFor(tab),
      fileName: tab.fileName,
      currentText: tab.controller.text,
      onRestore: (value) => _applyAssistantText(
        tab,
        value,
        'تمت استعادة الإصدار؛ احفظ الملف لتثبيته',
      ),
    );
  }

  void _openDiagnosticsPanel() {
    final tab = activeTab;
    final diagnostics = _getCurrentDiagnostics(tab);
    final structural = EditorSyntaxDiagnostics.analyze(
      tab.controller.text,
      tab.language,
    );
    final parserCount = (diagnostics.length - structural.length)
        .clamp(0, diagnostics.length)
        .toInt();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .62,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report_outlined, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 9),
                    Expanded(child: Text('مشكلات ${tab.fileName}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('${diagnostics.length}', style: const TextStyle(color: Color(0xFF94A3B8))),
                    IconButton(
                      tooltip: 'نسخ تقرير المشكلات ونصائح الإصلاح',
                      onPressed: () async {
                        final report = diagnostics.asMap().entries.map((entry) {
                          final index = entry.key;
                          final message = entry.value;
                          if (index >= parserCount) {
                            final issue = structural[index - parserCount];
                            return '${issue.line}:${issue.column} — ${issue.message}\n${_diagnosticAdvice(issue.message)}';
                          }
                          return '$message\n${_diagnosticAdvice(message)}';
                        }).join('\n\n');
                        await Clipboard.setData(ClipboardData(
                          text: report.isEmpty ? 'لا توجد مشكلات في الفحص الحالي.' : report,
                        ));
                        if (mounted) showMessage('تم نسخ تقرير المشكلات ونصائح الإصلاح');
                      },
                      icon: const Icon(Icons.copy_all_rounded),
                    ),
                    IconButton(onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: diagnostics.isEmpty
                    ? const Center(child: Text('لا توجد مشكلات معروفة في الفحص الحالي'))
                    : ListView.separated(
                        itemCount: diagnostics.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          if (index < parserCount) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.error_outline, color: Colors.orange),
                              title: Text(diagnostics[index], style: const TextStyle(fontSize: 12)),
                              subtitle: Text('فحص محلي\n${_diagnosticAdvice(diagnostics[index])}', maxLines: 3, overflow: TextOverflow.ellipsis),
                            );
                          }
                          final issue = structural[index - parserCount];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                            title: Text(issue.message, style: const TextStyle(fontSize: 12)),
                            subtitle: Text('السطر ${issue.line}، العمود ${issue.column}\n${_diagnosticAdvice(issue.message)}', maxLines: 3, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.my_location, size: 17),
                            onTap: () {
                              final offset = issue.offset
                                  .clamp(0, tab.controller.text.length)
                                  .toInt();
                              tab.controller.selection = TextSelection.collapsed(offset: offset);
                              _scheduleTabStateSave();
                              Navigator.pop(sheetContext);
                              _openEditorFullScreen();
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'الفحص بنيوي ومحلي؛ اضغط على المشكلة ذات الموقع للانتقال إليها. لا يحل محل محلل المترجم الرسمي.',
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: .55)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWorkspaceSettings() async {
    var draftFontSize = _editorFontSize;
    var draftExplorerVisible = explorerVisible;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refreshSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('إعدادات مساحة العمل',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 14),
                _dashboardPanel(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.folder_copy_rounded, color: Color(0xFF38BDF8)),
                    title: const Text('إظهار مستكشف الملفات',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: const Text('عرض شجرة ملفات المشروع بجانب مساحة العمل',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    value: draftExplorerVisible,
                    onChanged: (value) => refreshSheet(() => draftExplorerVisible = value),
                  ),
                ),
                const SizedBox(height: 10),
                _dashboardPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.text_fields_rounded, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 9),
                        const Expanded(child: Text('حجم خط المحرر',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                        Text('${draftFontSize.round()} px',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 5),
                      const Text('اضبط حجم النص لتسهيل القراءة والكتابة',
                        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                      Slider(
                        min: 10, max: 24, divisions: 14,
                        value: draftFontSize,
                        onChanged: (value) => refreshSheet(() => draftFontSize = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.save_rounded), label: const Text('حفظ الإعدادات'),
                )),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      _editorFontSize = draftFontSize.clamp(10.0, 24.0).toDouble();
      explorerVisible = draftExplorerVisible;
    });
    await _saveEditorPreferences();
    showMessage('تم حفظ إعدادات مساحة العمل');
  }

  Widget _dashboardPanel({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF131F30),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF30445E), width: 1),
    ),
    child: child,
  );

  Widget _dashboardToolCard(_DashboardAction action) => Material(
    color: const Color(0xFF101D36),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: action.onTap, borderRadius: BorderRadius.circular(19),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [action.color.withValues(alpha: .17), const Color(0xFF111B34), const Color(0xFF0C142A)]),
          border: Border.all(color: action.color.withValues(alpha: .38)),
          boxShadow: [BoxShadow(color: action.color.withValues(alpha: .10), blurRadius: 12)]),
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(action.icon, size: 27, color: action.color),
          const SizedBox(height: 6),
          Flexible(child: Text(action.label, maxLines: 2, softWrap: true,
            overflow: TextOverflow.visible, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFEAF2FF),
              fontSize: 10, height: 1.16, fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  );

  Widget _dashboardSectionTitle(IconData icon, String title) => Row(children: [
    Icon(icon, color: const Color(0xFF38BDF8), size: 20),
    const SizedBox(width: 8),
    Expanded(child: Text(title, style: const TextStyle(
      color: Color(0xFFE5EDF7), fontSize: 14, fontWeight: FontWeight.w700))),
  ]);

  Widget _dashboardProjectCard({required IconData icon, required String title,
    required String subtitle, required VoidCallback onTap, required Color accent}) =>
    Material(
      color: const Color(0xFF101B34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: .38)),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: .10), blurRadius: 13)],
          ),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1B293D),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 23),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE5EDF7),
                  fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
            ])),
            Icon(Icons.chevron_left_rounded, color: accent),
          ]),
        ),
      ),
    );

  void _showDashboardThemeInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('مظهر التطبيق',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('اختر المظهر المناسب، وسيُحفظ اختيارك تلقائيًا.',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 14),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: BishoThemeController.mode,
                builder: (context, mode, _) => Column(
                  children: [
                    _themeModeTile(sheetContext, ThemeMode.system, mode,
                      Icons.brightness_auto_rounded, 'حسب إعدادات الجهاز',
                      'يتبع الوضع الفاتح أو الداكن في Android'),
                    _themeModeTile(sheetContext, ThemeMode.dark, mode,
                      Icons.dark_mode_rounded, 'داكن',
                      'ألوان مريحة للعمل في الإضاءة المنخفضة'),
                    _themeModeTile(sheetContext, ThemeMode.light, mode,
                      Icons.light_mode_rounded, 'فاتح',
                      'واجهة واضحة في الإضاءة القوية'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeModeTile(
    BuildContext sheetContext,
    ThemeMode value,
    ThemeMode selected,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final active = value == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .10)
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(
              color: active ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          leading: Icon(icon, color: active
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)),
          trailing: active
              ? Icon(Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary)
              : const Icon(Icons.circle_outlined),
          onTap: () async {
            await BishoThemeController.set(value);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  static const String _enabledExtensionsKey = 'bisho_enabled_editor_extensions_v1';
  static const String _customExtensionsKey = 'bisho_custom_editor_extensions_v1';

  Future<void> _showPluginsHub() async {
    final entries = <_EditorExtensionEntry>[
      _EditorExtensionEntry('json_format', 'تنسيق JSON', 'ترتيب المسافات وإظهار بنية JSON بوضوح', 'تنسيق البيانات', Icons.data_object_rounded, const Color(0xFF08B9F4)),
      _EditorExtensionEntry('json_minify', 'ضغط JSON', 'إزالة المسافات غير الضرورية لتقليل الحجم', 'تنسيق البيانات', Icons.compress_rounded, const Color(0xFF8B42F5)),
      _EditorExtensionEntry('base64_encode', 'ترميز Base64', 'تحويل النص إلى Base64', 'الترميز والتحويل', Icons.lock_rounded, const Color(0xFF19D889)),
      _EditorExtensionEntry('base64_decode', 'فك Base64', 'استعادة النص من Base64', 'الترميز والتحويل', Icons.lock_open_rounded, const Color(0xFFFFC247)),
      _EditorExtensionEntry('url_encode', 'ترميز URL', 'تهيئة النص للاستخدام داخل عناوين URL', 'الترميز والتحويل', Icons.link_rounded, const Color(0xFF08B9F4)),
      _EditorExtensionEntry('url_decode', 'فك URL', 'فك ترميز النص الموجود داخل عنوان URL', 'الترميز والتحويل', Icons.link_off_rounded, const Color(0xFF247BFF)),
      _EditorExtensionEntry('sort_lines', 'ترتيب الأسطر', 'ترتيب الأسطر أبجدياً داخل التحديد أو الملف', 'تحرير النص', Icons.sort_by_alpha_rounded, const Color(0xFF8B42F5)),
      _EditorExtensionEntry('unique_lines', 'حذف الأسطر المكررة', 'إزالة الأسطر المتكررة مع الاحتفاظ بأول ظهور', 'تحرير النص', Icons.filter_alt_rounded, const Color(0xFF19D889)),
      _EditorExtensionEntry('trim_trailing_whitespace', 'تنظيف نهايات الأسطر', 'إزالة المسافات وعلامات الجدولة غير الضرورية من نهاية كل سطر', 'تنظيف النص', Icons.cleaning_services_rounded, const Color(0xFF08B9F4)),
      _EditorExtensionEntry('normalize_line_endings', 'توحيد نهايات الأسطر', 'تحويل CRLF وCR إلى LF لتوحيد تنسيق الملف', 'تنظيف النص', Icons.format_line_spacing_rounded, const Color(0xFF247BFF)),
      _EditorExtensionEntry('tabs_to_spaces', 'تحويل TAB إلى مسافات', 'استبدال كل علامة TAB بأربع مسافات', 'تنظيف النص', Icons.space_bar_rounded, const Color(0xFFFFC247)),
    ];
    final prefs = await SharedPreferences.getInstance();
    final customPacks = prefs.getStringList(_customExtensionsKey) ?? <String>[];
    for (final packedEntry in customPacks) {
      try {
        final decoded = jsonDecode(packedEntry);
        if (decoded is! Map<String, dynamic>) continue;
        final manifest = EditorExtensionManifest.decode(jsonEncode({
          'format': EditorExtensionManifest.format,
          'version': EditorExtensionManifest.version,
          'extensions': [decoded],
        }));
        final extension = manifest.extensions.single;
        entries.add(_EditorExtensionEntry(
          extension.id,
          extension.title,
          extension.description,
          extension.category,
          Icons.extension_rounded,
          const Color(0xFF38BDF8),
          operationId: extension.operation,
        ));
      } catch (_) {
        // Ignore invalid legacy entries; importing never enables code execution.
      }
    }
    final stored = prefs.getStringList(_enabledExtensionsKey);
    var enabled = stored == null
        ? entries.where((entry) => entry.operationId == null)
            .map((entry) => entry.id).toSet()
        : stored.toSet();
    if (!mounted) return;
    final searchController = TextEditingController();
    var query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refreshSheet) {
          final normalized = query.trim().toLowerCase();
          final filtered = entries.where((entry) =>
            normalized.isEmpty ||
            entry.title.toLowerCase().contains(normalized) ||
            entry.description.toLowerCase().contains(normalized) ||
            entry.category.toLowerCase().contains(normalized),
          ).toList();
          final activeCount = entries.where((entry) => enabled.contains(entry.id)).length;

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                    child: Row(children: [
                      const Icon(Icons.extension_rounded, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 9),
                      const Expanded(child: Text('مدير الإضافات والأدوات',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      Text('${activeCount}/${entries.length}',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w800)),
                      IconButton(onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) => refreshSheet(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن إضافة أو وظيفة...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty ? null : IconButton(
                          onPressed: () {
                            searchController.clear();
                            refreshSheet(() => query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      const Expanded(child: Text('اضغط على الإضافة لتشغيلها، أو استخدم المفتاح لتفعيلها وتعطيلها.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10))),
                      TextButton(
                        onPressed: () async {
                          enabled = entries.map((entry) => entry.id).toSet();
                          await prefs.setStringList(_enabledExtensionsKey, enabled.toList());
                          refreshSheet(() {});
                        },
                        child: const Text('تفعيل الكل'),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _importEditorExtensionPack();
                          if (!mounted) return;
                          Navigator.pop(sheetContext);
                          await _showPluginsHub();
                        },
                        icon: const Icon(Icons.file_upload_outlined, size: 17),
                        label: const Text('استيراد حزمة إضافات JSON'),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                      ? const Center(child: Text('لا توجد إضافات مطابقة للبحث.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 5),
                          itemBuilder: (_, index) {
                            final entry = filtered[index];
                            final isEnabled = enabled.contains(entry.id);
                            return Card(
                              color: const Color(0xFF101D36),
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: entry.color.withValues(alpha: .14),
                                  child: Icon(entry.icon, color: entry.color, size: 20),
                                ),
                                title: Text(entry.title,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                subtitle: Text('${entry.category} • ${entry.description}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                trailing: Switch(
                                  value: isEnabled,
                                  onChanged: (value) async {
                                    if (value) {
                                      enabled.add(entry.id);
                                    } else {
                                      enabled.remove(entry.id);
                                    }
                                    await prefs.setStringList(_enabledExtensionsKey, enabled.toList());
                                    refreshSheet(() {});
                                  },
                                ),
                                onTap: isEnabled ? () {
                                  Navigator.pop(sheetContext);
                                  _runEditorExtension(entry.operationId ?? entry.id);
                                } : null,
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    searchController.dispose();
  }

  Future<void> _importEditorExtensionPack() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('تعذر قراءة ملف الحزمة.');
      }
      final manifest = EditorExtensionManifest.decode(utf8.decode(bytes));
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_customExtensionsKey) ?? <String>[];
      final existingIds = <String>{
        'json_format', 'json_minify', 'base64_encode', 'base64_decode',
        'url_encode', 'url_decode', 'sort_lines', 'unique_lines',
        'trim_trailing_whitespace', 'normalize_line_endings', 'tabs_to_spaces',
      };
      for (final item in current) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic> && decoded['id'] is String) {
            existingIds.add(decoded['id'] as String);
          }
        } catch (_) {
          // Invalid old entries are ignored and replaced by a valid import.
        }
      }
      final duplicates = manifest.extensions
          .where((extension) => existingIds.contains(extension.id))
          .map((extension) => extension.id)
          .toList();
      if (duplicates.isNotEmpty) {
        throw FormatException('معرّفات موجودة مسبقاً: ${duplicates.join(', ')}');
      }
      if (current.length + manifest.extensions.length > 60) {
        throw const FormatException('وصلت إلى الحد الأقصى وهو 60 إضافة مخصصة.');
      }
      final merged = [
        ...current,
        ...manifest.extensions.map((extension) => jsonEncode(extension.toJson())),
      ];
      await prefs.setStringList(_customExtensionsKey, merged);
      showMessage('تم استيراد ${manifest.extensions.length} إضافة. راجع تفعيلها من مدير الإضافات.');
    } catch (error) {
      showMessage('تعذر استيراد حزمة الإضافات: $error');
    }
  }

  Future<void> _runEditorExtension(String operation) async {
    if (tabs.isEmpty) {
      showMessage('افتح ملفاً أولاً لاستخدام الإضافة');
      return;
    }
    final tab = activeTab;
    final controller = tab.controller;
    final source = controller.text;
    final selection = controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final start = hasSelection ? selection.start : 0;
    final end = hasSelection ? selection.end : source.length;
    final input = source.substring(start, end);
    String output;
    String success;

    try {
      switch (operation) {
        case 'json_format':
          output = const JsonEncoder.withIndent('  ').convert(jsonDecode(input));
          success = 'تم تنسيق JSON';
          break;
        case 'json_minify':
          output = jsonEncode(jsonDecode(input));
          success = 'تم ضغط JSON وإزالة المسافات';
          break;
        case 'base64_encode':
          output = base64Encode(utf8.encode(input));
          success = 'تم ترميز النص بصيغة Base64';
          break;
        case 'base64_decode':
          output = utf8.decode(base64Decode(input.trim()));
          success = 'تم فك ترميز Base64';
          break;
        case 'url_encode':
          output = Uri.encodeComponent(input);
          success = 'تم ترميز النص للرابط';
          break;
        case 'url_decode':
          output = Uri.decodeComponent(input);
          success = 'تم فك ترميز الرابط';
          break;
        case 'sort_lines':
          final lines = input.split('\n')..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          output = lines.join('\n');
          success = 'تم ترتيب الأسطر أبجدياً';
          break;
        case 'unique_lines':
          final seen = <String>{};
          output = input.split('\n').where((line) => seen.add(line)).join('\n');
          success = 'تم حذف الأسطر المكررة';
          break;
        case 'trim_trailing_whitespace':
          output = input.split('\n')
              .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
              .join('\n');
          success = 'تم تنظيف المسافات من نهايات الأسطر';
          break;
        case 'normalize_line_endings':
          output = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
          success = 'تم توحيد نهايات الأسطر إلى LF';
          break;
        case 'tabs_to_spaces':
          output = input.replaceAll('\t', '    ');
          success = 'تم تحويل علامات TAB إلى أربع مسافات';
          break;
        default:
          return;
      }
    } catch (error) {
      showMessage('تعذر تنفيذ الإضافة: ${error is FormatException ? error.message : error}');
      return;
    }

    if (output == input) {
      showMessage('لا توجد تغييرات مطلوبة');
      return;
    }

    final updated = source.replaceRange(start, end, output);
    final previewLines = output.split('\n');
    final originalLines = input.split('\n');
    final previewAccepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.preview_rounded, color: Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            Expanded(child: Text('معاينة قبل التطبيق')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(success, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.remove_circle_outline, size: 16),
                      label: Text('${originalLines.length} سطر قبل'),
                    ),
                    Chip(
                      avatar: const Icon(Icons.add_circle_outline, size: 16),
                      label: Text('${previewLines.length} سطر بعد'),
                    ),
                    Chip(label: Text('${output.length} حرف في الناتج')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('النص قبل التعديل', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF475569)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      input.length > 2500
                          ? '${input.substring(0, 2500)}\n… تم اختصار النص السابق.'
                          : input,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('النص بعد التعديل', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 280),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      output.length > 6000
                          ? '${output.substring(0, 6000)}\n\n… تم اختصار المعاينة؛ سيُطبّق الناتج كاملاً.'
                          : output,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'لن يتغير الملف حتى تضغط «تطبيق». يمكنك الإلغاء للعودة دون أي تعديل.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('تطبيق التغييرات'),
          ),
        ],
      ),
    );

    if (previewAccepted != true || !mounted) return;
    if (!tabs.contains(tab) || controller.text != source) {
      showMessage('تغير الملف أثناء المعاينة؛ أعد تشغيل الإضافة لتجنب استبدال تعديلات أحدث');
      return;
    }

    controller.value = controller.value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: start + output.length),
      composing: TextRange.empty,
    );
    tab.isSaved = false;
    _scheduleTabStateSave();
    if (mounted) setState(() {});
    showMessage(success);
  }


  void _showLanguageCapabilities() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('دليل اللغات والقدرات',
                      style: TextStyle(fontWeight: FontWeight.w700))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: LanguageEngineManager.capabilities.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final capability = LanguageEngineManager.capabilities[index];
                    final hasPreviewRoute = capability.extensions.any((extension) =>
                        LanguageEngineManager.engineForFile('sample.$extension') !=
                        LanguageEngine.unsupported);
                    final notes = capability.note.isNotEmpty
                        ? capability.note
                        : capability.executionEngine
                            ? 'توجد معاينة أو بيئة تنفيذ محددة لهذه اللغة.'
                            : hasPreviewRoute
                                ? 'توجد أداة عرض أو تحقق للملفات، دون تشغيل برنامج مستقل.'
                                : 'تحرير وتلوين؛ لا يوجد محرك تشغيل مضمّن حالياً.';
                    return ExpansionTile(
                      title: Text(capability.language,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(notes, style: const TextStyle(fontSize: 10)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Chip(label: Text(capability.syntaxHighlighting ? 'تلوين مدعوم' : 'نص عادي')),
                              Chip(label: Text(capability.structuralDiagnostics ? 'فحص بنيوي' : 'بدون فحص بنيوي')),
                              Chip(label: Text(hasPreviewRoute ? 'معاينة/عرض متاح' : 'لا يوجد محرك تشغيل')),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'الامتدادات: ${capability.extensions.map((extension) => ".$extension").join("، ")}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditorInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('معلومات المحرر'),
        content: const Text('يوفر Bisho IDE أدوات إنشاء الملفات والمشاريع، والحفظ والتصدير، والبحث والاستبدال، والتنقل بين الأسطر، وإكمال الكود، ومعاينة اللغات المدعومة. نضيف الميزات تدريجياً بعد اختبارها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget toolButton(
    IconData icon,
    String label,
    VoidCallback action,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: const Color(0xFF38BDF8),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

  // ignore: unused_element
class _DashboardWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6
      ..shader = const LinearGradient(colors: [Color(0x0012AFFF), Color(0xFF087DFF), Color(0xFF12AFFF)])
        .createShader(Offset.zero & size);
    final purple = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5
      ..shader = const LinearGradient(colors: [Color(0x002D65FF), Color(0xFF8B24FF), Color(0xFFB21FFF)])
        .createShader(Offset.zero & size);
    final a = Path()..moveTo(0, size.height * .18)
      ..cubicTo(size.width * .22, size.height * .62, size.width * .36, size.height * .80, size.width * .58, size.height * .52)
      ..cubicTo(size.width * .76, size.height * .27, size.width * .88, size.height * .20, size.width, size.height * .42);
    final b = Path()..moveTo(0, size.height * .38)
      ..cubicTo(size.width * .22, size.height * .82, size.width * .42, size.height * .93, size.width * .62, size.height * .67)
      ..cubicTo(size.width * .78, size.height * .44, size.width * .91, size.height * .32, size.width, size.height * .56);
    canvas.drawPath(a, blue);
    canvas.drawPath(b, purple);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EditorExtensionEntry {
  final String id;
  final String title;
  final String description;
  final String category;
  final IconData icon;
  final Color color;
  final String? operationId;

  const _EditorExtensionEntry(
    this.id, this.title, this.description, this.category, this.icon, this.color, {
    this.operationId,
  });
}

class _DashboardAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _DashboardAction(this.icon, this.label, this.onTap, this.color);
}

/// شاشة مستقلة للطرفية تستغل كامل مساحة التطبيق بدلاً من لوحة سفلية قصيرة.
class TerminalFullScreenScreen extends StatelessWidget {
  const TerminalFullScreenScreen({
    super.key,
    required this.files,
    required this.projectUri,
    required this.projectName,
    required this.onOpenFile,
  });

  final SafFileService files;
  final String? projectUri;
  final String projectName;
  final Future<void> Function(SafDocumentFile file, String parentUri) onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF080D19),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B2D),
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: Color(0xFF26374E))),
          title: const Row(
            children: [
              Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8)),
              SizedBox(width: 9),
              Text('طرفية Bisho', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          leading: IconButton(
            tooltip: 'العودة إلى المحرر',
            icon: const Icon(Icons.fullscreen_exit_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BishoTerminalPanel(
                files: files,
                projectUri: projectUri,
                projectName: projectName,
                onOpenFile: onOpenFile,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شاشة مستقلة للمحرر؛ تستخدم نفس CodeController حتى تبقى التعديلات
/// والتبويبات والحالة محفوظة عند الرجوع إلى الواجهة الرئيسية.
class EditorFullScreenScreen extends StatefulWidget {
  const EditorFullScreenScreen({
    super.key,
    required this.tab,
    required this.fontSize,
    required this.onSave,
    required this.onFontSizeChange,
    required this.onShowCompletions,
    required this.onSearch,
    required this.onPreview,
    required this.onFlutterPreview,
  });

  final EditorTab tab;
  final double fontSize;
  final Future<void> Function() onSave;
  final void Function(double delta) onFontSizeChange;
  final Future<void> Function() onShowCompletions;
  final Future<void> Function(bool replaceMode) onSearch;
  final Future<void> Function() onPreview;
  final void Function() onFlutterPreview;

  @override
  State<EditorFullScreenScreen> createState() =>
      _EditorFullScreenScreenState();
}

class _EditorFullScreenScreenState extends State<EditorFullScreenScreen> {
  static const String _wordWrapPreferenceKey = 'bisho_editor_word_wrap';
  static const String _minimapPreferenceKey = 'bisho_editor_minimap';
  late double _fontSize;
  bool _wordWrap = false;
  bool _showMinimap = true;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _restoreWordWrapPreference();
  }

  Future<void> _restoreWordWrapPreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedValue = preferences.getBool(_wordWrapPreferenceKey) ?? false;
      final savedMinimap = preferences.getBool(_minimapPreferenceKey) ?? true;
      if (!mounted) return;
      setState(() {
        _wordWrap = savedValue;
        _showMinimap = savedMinimap;
      });
    } catch (_) {
      // Word wrap remains available with its default when preferences fail.
    }
  }

  Future<void> _toggleWordWrap() async {
    final nextValue = !_wordWrap;
    setState(() => _wordWrap = nextValue);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_wordWrapPreferenceKey, nextValue);
    } catch (_) {
      // The current session setting remains active if persistence is unavailable.
    }
  }

  Future<void> _toggleMinimap() async {
    final nextValue = !_showMinimap;
    setState(() => _showMinimap = nextValue);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_minimapPreferenceKey, nextValue);
    } catch (_) {
      // Keep the current session setting when persistence is unavailable.
    }
  }

  Widget _buildMinimap(EditorTab tab) {
    if (!_showMinimap) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: tab.controller,
      builder: (context, value, _) {
        final lines = EditorMinimapModel.fromText(
          value.text,
          maximumLines: 500,
        );
        final cursor = value.selection.isValid
            ? value.selection.extentOffset.clamp(0, value.text.length).toInt()
            : value.text.length;
        final currentLine = '\n'.allMatches(value.text.substring(0, cursor)).length + 1;
        return Container(
          width: 54,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1727),
            border: Border(left: BorderSide(color: Color(0xFF26374E))),
          ),
          child: Column(children: [
            const SizedBox(height: 5),
            const Text('MAP', style: TextStyle(
              color: Color(0xFF64748B), fontSize: 7, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                final active = line.number == currentLine;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setCursor(line.startOffset),
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(vertical: .4),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: active ? const Color(0x5538BDF8) : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      line.text.isEmpty ? ' ' : line.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 4.2,
                        height: 1,
                        color: active ? const Color(0xFF7DD3FC) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                );
              },
            )),
          ]),
        );
      },
    );
  }

  void _changeFontSize(double delta) {
    widget.onFontSizeChange(delta);
    setState(() {
      _fontSize = (_fontSize + delta).clamp(10.0, 24.0).toDouble();
    });
  }

  void _insertSymbol(String symbol) {
    final controller = widget.tab.controller;
    final nextValue = EditorSymbolInsert.apply(
      text: controller.text,
      selection: controller.selection,
      symbol: symbol,
    );
    controller.value = nextValue;
  }

  void _moveCursor({int horizontal = 0, int vertical = 0}) {
    final controller = widget.tab.controller;
    final text = controller.text;
    final selection = controller.selection;
    final current = selection.isValid
        ? selection.extentOffset.clamp(0, text.length).toInt()
        : text.length;

    int target;
    if (horizontal != 0) {
      target = (current + horizontal).clamp(0, text.length).toInt();
    } else {
      final lineStart = text.lastIndexOf('\\n', current - 1) + 1;
      final lineEndFound = text.indexOf('\\n', current);
      final lineEnd = lineEndFound == -1 ? text.length : lineEndFound;
      final column = current - lineStart;
      if (vertical < 0) {
        if (lineStart == 0) return;
        final previousEnd = lineStart - 1;
        final previousStart = text.lastIndexOf('\\n', previousEnd - 1) + 1;
        target = (previousStart + column).clamp(previousStart, previousEnd).toInt();
      } else {
        if (lineEnd == text.length) return;
        final nextStart = lineEnd + 1;
        final nextEndFound = text.indexOf('\\n', nextStart);
        final nextEnd = nextEndFound == -1 ? text.length : nextEndFound;
        target = (nextStart + column).clamp(nextStart, nextEnd).toInt();
      }
    }
    controller.selection = TextSelection.collapsed(offset: target);
  }

  void _setCursor(int offset, {bool extendSelection = false}) {
    final controller = widget.tab.controller;
    final safe = offset.clamp(0, controller.text.length).toInt();
    final current = controller.selection;
    controller.selection = extendSelection && current.isValid
        ? TextSelection(baseOffset: current.baseOffset, extentOffset: safe)
        : TextSelection.collapsed(offset: safe);
  }

  void _selectCurrentWord() {
    final controller = widget.tab.controller;
    final offset = controller.selection.isValid
        ? controller.selection.extentOffset
        : controller.text.length;
    final selected = EditorTextNavigation.selectCurrentWord(controller.text, offset);
    controller.selection = selected;
  }

  Future<void> _copySelection() async {
    final controller = widget.tab.controller;
    final selection = controller.selection;
    final text = selection.isValid && !selection.isCollapsed
        ? controller.text.substring(selection.start, selection.end)
        : controller.text;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _cutSelection() async {
    final controller = widget.tab.controller;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final selectedText = controller.text.substring(selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: selectedText));
    controller.value = EditorTextNavigation.replaceSelection(
      controller.text,
      selection,
      '',
    );
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null) return;
    final controller = widget.tab.controller;
    final selection = controller.selection;
    controller.value = EditorTextNavigation.replaceSelection(
      controller.text,
      selection,
      pasted,
    );
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    final controller = widget.tab.controller;
    final selection = controller.selection;
    final offset = selection.isValid
        ? selection.extentOffset.clamp(0, controller.text.length).toInt()
        : controller.text.length;
    final extend = event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight ||
        keyboard.isShiftPressed;

    if (control && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyF) {
      widget.onSearch(false);
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyH) {
      widget.onSearch(true);
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.space) {
      widget.onShowCompletions();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyD) {
      _selectCurrentWord();
      return KeyEventResult.handled;
    }
    if (control && (event.logicalKey == LogicalKeyboardKey.equal ||
        event.logicalKey == LogicalKeyboardKey.add)) {
      _changeFontSize(1);
      return KeyEventResult.handled;
    }
    if (control && (event.logicalKey == LogicalKeyboardKey.minus ||
        event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _changeFontSize(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _setCursor(control ? 0 : EditorTextNavigation.lineStart(controller.text, offset),
          extendSelection: extend);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _setCursor(control ? controller.text.length :
          EditorTextNavigation.lineEnd(controller.text, offset),
          extendSelection: extend);
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _setCursor(EditorTextNavigation.moveByWord(controller.text, offset, forward: false),
          extendSelection: extend);
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _setCursor(EditorTextNavigation.moveByWord(controller.text, offset, forward: true),
          extendSelection: extend);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildCursorPad() {
    Widget arrow(IconData icon, String tooltip, int horizontal, int vertical) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFF1B293D),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _moveCursor(horizontal: horizontal, vertical: vertical),
            child: SizedBox(
              width: 38,
              height: 34,
              child: Icon(icon, size: 18, color: const Color(0xFFBAE6FD)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(
          bottom: BorderSide(color: Color(0xFF26334D)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location, size: 16, color: Color(0xFF38BDF8)),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'التحكم بالمؤشر',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ),
          arrow(Icons.keyboard_arrow_left, 'تحريك المؤشر يساراً', -1, 0),
          const SizedBox(width: 5),
          arrow(Icons.keyboard_arrow_up, 'السطر السابق', 0, -1),
          const SizedBox(width: 5),
          arrow(Icons.keyboard_arrow_down, 'السطر التالي', 0, 1),
          const SizedBox(width: 5),
          arrow(Icons.keyboard_arrow_right, 'تحريك المؤشر يميناً', 1, 0),
        ],
      ),
    );
  }

  Widget _buildMobileSymbolBar() {
    const symbols = <String>[
      'TAB', '(', '{', '[', ';', ':', '=', '=>', '.', ',', '->',
      "'", '"', '`', '&&', '||', '!',
    ];
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(
          bottom: BorderSide(color: Color(0xFF26334D)),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: symbols.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final symbol = symbols[index];
            final label = symbol == 'TAB' ? '⇥' : symbol;
            return Material(
              color: const Color(0xFF1B293D),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _insertSymbol(symbol),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 38),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF304158)),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFBAE6FD),
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF080D19),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B2D),
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: Color(0xFF26374E))),
          leading: IconButton(
            tooltip: 'العودة إلى Bisho IDE',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tab.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                tab.language,
                style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'معاينة / تشغيل الملف الحالي',
              onPressed: widget.onPreview,
              icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF19D889)),
            ),
            IconButton(
              tooltip: 'بناء ومعاينة Flutter',
              onPressed: widget.onFlutterPreview,
              icon: const Icon(Icons.phone_android_rounded, color: Color(0xFF38BDF8)),
            ),
            PopupMenuButton<String>(
              tooltip: 'أدوات التحرير',
              onSelected: (action) {
                switch (action) {
                  case 'select_word':
                    _selectCurrentWord();
                    break;
                  case 'copy':
                    _copySelection();
                    break;
                  case 'cut':
                    _cutSelection();
                    break;
                  case 'paste':
                    _pasteClipboard();
                    break;
                  case 'wrap':
                    _toggleWordWrap();
                    break;
                  case 'minimap':
                    _toggleMinimap();
                    break;
                  case 'complete':
                    widget.onShowCompletions();
                    break;
                  case 'smaller':
                    _changeFontSize(-1);
                    break;
                  case 'larger':
                    _changeFontSize(1);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'select_word',
                  child: Row(
                    children: [
                      Icon(Icons.select_all, size: 20),
                      const SizedBox(width: 12),
                      Text('تحديد الكلمة الحالية (Ctrl+D)'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 20),
                      const SizedBox(width: 12),
                      Text('نسخ المحدد'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cut',
                  child: Row(
                    children: [
                      Icon(Icons.content_cut, size: 20),
                      const SizedBox(width: 12),
                      Text('قص المحدد'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'paste',
                  child: Row(
                    children: [
                      Icon(Icons.content_paste, size: 20),
                      const SizedBox(width: 12),
                      Text('لصق'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'complete',
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 12),
                    Text('الإكمال التلقائي'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'smaller',
                  child: Row(children: [
                    Icon(Icons.text_decrease, size: 20),
                    SizedBox(width: 12),
                    Text('تصغير الخط'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'larger',
                  child: Row(children: [
                    Icon(Icons.text_increase, size: 20),
                    SizedBox(width: 12),
                    Text('تكبير الخط'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'wrap',
                  child: Row(
                    children: [
                      Icon(_wordWrap ? Icons.wrap_text : Icons.notes, size: 20),
                      const SizedBox(width: 12),
                      Text(_wordWrap ? 'تعطيل التفاف الأسطر' : 'تفعيل التفاف الأسطر'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'minimap',
                  child: Row(
                    children: [
                      Icon(_showMinimap ? Icons.map_rounded : Icons.map_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(_showMinimap ? 'إخفاء خريطة الكود' : 'إظهار خريطة الكود'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.edit_note),
            ),
            IconButton(
              tooltip: 'حفظ الملف',
              onPressed: widget.onSave,
              icon: const Icon(Icons.save_rounded),
            ),
          ],
        ),

        body: SafeArea(
          child: Focus(
            onKeyEvent: _handleEditorKey,
            child: Column(
            children: [
              _buildMobileSymbolBar(),
              _buildCursorPad(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF080D19),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF26334D)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CodeTheme(
                data: CodeThemeData(styles: monokaiSublimeTheme),
                child: Row(children: [
                  Expanded(child: CodeField(
                    key: ValueKey('fullscreen-${tab.id}'),
                    controller: tab.controller,
                    expands: true,
                    wrap: _wordWrap,
                    padding: const EdgeInsets.all(14),
                    textStyle: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: _fontSize,
                    ),
                    gutterStyle: const GutterStyle(
                      showLineNumbers: true,
                      showErrors: true,
                      showFoldingHandles: true,
                    ),
                  )),
                  if (_showMinimap) _buildMinimap(tab),
                ]),
              ),
            ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
