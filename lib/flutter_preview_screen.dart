import 'dart:convert';

import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/services/flutter_pubspec_validator.dart';

import 'core/services/saf_file_service.dart';
import 'core/services/github_repository_service.dart';
import 'core/services/project_scaffold_repair_service.dart';
import 'core/services/project_health_analyzer.dart';
import 'core/services/local_build_environment.dart';
import 'core/services/engine_health_report.dart';
import 'core/services/local_build_runner.dart';
import 'core/services/local_build_engine_installer.dart';
import 'core/services/alpine_rootfs_installer.dart';
import 'core/services/build_history_store.dart';
import 'core/services/remote_build_settings.dart';
import 'features/tools/ide_tool_sheets.dart';

class FlutterPreviewScreen extends StatefulWidget {
  final String projectName;
  final String? projectUri;
  final SafFileService safFiles;
  final Future<void> Function() onPickProject;
  final String? Function() projectUriProvider;
  final String Function() projectNameProvider;

  const FlutterPreviewScreen({
    super.key,
    this.projectName = 'لا يوجد مشروع',
    required this.projectUri,
    required this.safFiles,
    required this.onPickProject,
    required this.projectUriProvider,
    required this.projectNameProvider,
  });

  @override
  State<FlutterPreviewScreen> createState() => _FlutterPreviewScreenState();
}

class _FlutterPreviewScreenState extends State<FlutterPreviewScreen> {
  static const _background = Color(0xFF0B1020);
  static const _panelColor = Color(0xFF111B30);
  static const _cyan = Color(0xFF38BDF8);
  static const _muted = Color(0xFF94A3B8);

  final _repoController = TextEditingController();
  final _workflowController = TextEditingController(text: 'main.yml');
  final _branchController = TextEditingController(text: 'main');
  final _versionController = TextEditingController(text: '3.47.9');
  final _tokenController = TextEditingController();
  final _githubService = GitHubRepositoryService();
  final _localBuildService = LocalBuildEnvironmentService();
  late final _localBuildRunner = LocalBuildRunner();
  final _engineInstaller = LocalBuildEngineInstaller();
  final _alpineInstaller = AlpineRootfsInstaller();
  bool _alpineInstalling = false;
  final _engineUrlController = TextEditingController();
  final _engineShaController = TextEditingController();
  StreamSubscription<EngineInstallProgress>? _engineInstallSubscription;
  bool _engineInstalling = false;
  bool _probingLocalEngine = false;
  StreamSubscription<LocalBuildProgress>? _localBuildSubscription;
  bool _localBuildRunning = false;
  static const _localBuildModePreferenceKey = 'bisho_local_build_mode';
  String _localBuildMode = 'debug';
  bool _localBuildModeChanged = false;
  bool _remoteSettingsChanged = false;
  Future<void> _remoteSettingsWrite = Future<void>.value();
  String _localBuildLog = '';
  final StringBuffer _fullBuildLog = StringBuffer();
  BuildHistoryStore? _buildHistoryStore;

  Future<BuildHistoryStore?> _ensureBuildHistoryStore() async {
    if (_buildHistoryStore != null) return _buildHistoryStore;
    try {
      final base = await getApplicationDocumentsDirectory();
      _buildHistoryStore =
          BuildHistoryStore(Directory('${base.path}/bisho_build_history'));
    } catch (_) {
      return null;
    }
    return _buildHistoryStore;
  }

  Future<void> _recordBuildHistory({required bool success}) async {
    try {
      final store = await _ensureBuildHistoryStore();
      if (store == null || _fullBuildLog.isEmpty) return;
      await store.record(
        log: _fullBuildLog.toString(),
        success: success,
        mode: _localBuildMode,
        projectName: _projectName,
      );
    } catch (_) {
      // Build history is optional and must not affect the build result.
    }
  }

  Future<void> _openBuildAnalysis() async {
    final store = await _ensureBuildHistoryStore();
    if (!mounted) return;
    await showBuildAnalysisSheet(
      context,
      log: _fullBuildLog.isEmpty ? _localBuildLog : _fullBuildLog.toString(),
      store: store,
    );
  }
  LocalBuildEnvironment? _localBuildEnvironment;
  bool _checkingLocalBuild = false;
  GitHubAccount? _githubAccount;
  bool _connectingGitHub = false;

  String? _projectUri;
  String _projectName = 'لا يوجد مشروع';
  bool _checkingProject = false;
  bool _repairingProject = false;
  bool _repairAndroidFiles = true;
  bool _repairEntryPoint = true;
  bool _isFlutterSource = false;
  bool _hasAndroidPlatform = false;
  bool _isFlutterProject = false;
  List<ProjectHealthIssue> _projectIssues = const [];
  String _projectMessage = 'اختر مجلد مشروع Flutter لفحصه';
  bool _busy = false;
  String _status = 'لم يبدأ أي بناء';
  String _log = 'سيظهر هنا رد GitHub وحالة عملية البناء عند الاتصال.';
  String? _runUrl;
  String? _runId;
  DateTime? _dispatchTime;
  String? _workflowStatus;
  String? _workflowConclusion;

  @override
  void initState() {
    super.initState();
    _projectUri = widget.projectUri;
    _projectName = widget.projectName;
    _repoController.text = _projectName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    _checkProject();
    _inspectLocalBuildEnvironment();
    _loadGitHubSession();
    _restoreLocalBuildMode();
    _restoreRemoteBuildSettings();
  }

  Future<void> _restoreRemoteBuildSettings() async {
    try {
      final settings = await RemoteBuildSettings.load();
      if (!mounted || _remoteSettingsChanged) return;
      setState(() {
        if (settings.repository.isNotEmpty) {
          _repoController.text = settings.repository;
        }
        _workflowController.text = settings.workflow;
        _branchController.text = settings.branch;
        _versionController.text = settings.flutterVersion;
      });
    } catch (_) {
      // Saved cloud settings are optional; keep the current defaults.
    }
  }

  void _saveRemoteBuildSettings() {
    _remoteSettingsChanged = true;
    final settings = RemoteBuildSettings(
      repository: _repoController.text.trim(),
      workflow: _workflowController.text.trim().isEmpty
          ? 'main.yml' : _workflowController.text.trim(),
      branch: _branchController.text.trim().isEmpty
          ? 'main' : _branchController.text.trim(),
      flutterVersion: _versionController.text.trim().isEmpty
          ? '3.47.9' : _versionController.text.trim(),
    );
    _remoteSettingsWrite = _remoteSettingsWrite.then((_) async {
      try {
        await settings.save();
      } catch (_) {
        // Persistence failure must never block a remote build.
      }
    });
  }

  Future<void> _restoreLocalBuildMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_localBuildModePreferenceKey);
      if (!mounted || _localBuildModeChanged) return;
      if (saved == 'debug' || saved == 'release') {
        setState(() => _localBuildMode = saved!);
      }
    } catch (_) {
      // A missing preference must not block local build setup.
    }
  }

  Future<void> _setLocalBuildMode(String mode) async {
    if (mode != 'debug' && mode != 'release') return;
    setState(() {
      _localBuildModeChanged = true;
      _localBuildMode = mode;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localBuildModePreferenceKey, mode);
    } catch (_) {
      // Keep the current selection even if preference storage is unavailable.
    }
  }

  @override
  void dispose() {
    _repoController.dispose();
    _workflowController.dispose();
    _branchController.dispose();
    _versionController.dispose();
    _tokenController.dispose();
    _githubService.close();
    _localBuildSubscription?.cancel();
    _engineInstallSubscription?.cancel();
    _engineInstaller.dispose();
    unawaited(_alpineInstaller.cancel());
    _engineUrlController.dispose();
    _engineShaController.dispose();
    super.dispose();
  }

  Future<void> _startLocalBuild() async {
    final projectUri = _projectUri;
    final environment = _localBuildEnvironment;
    if (projectUri == null || projectUri.isEmpty || !_isFlutterProject) {
      _showMessage('افتح مشروع Flutter أولاً.');
      return;
    }
    if (environment == null || !environment.deviceSupported || !environment.engineInstalled) {
      _showMessage('محرك البناء أو متطلبات الجهاز غير مكتملة.');
      return;
    }
    _fullBuildLog.clear();
    setState(() {
      _localBuildRunning = true;
      _localBuildLog = 'جارٍ نسخ ملفات المشروع إلى مساحة البناء الخاصة بالتطبيق...';
    });
    _localBuildSubscription?.cancel();
    _localBuildSubscription = _localBuildRunner.progress.listen((event) {
      if (_fullBuildLog.length < 400000) _fullBuildLog.writeln(event.message);
      if (!mounted) return;
      setState(() {
        final lines = <String>[..._localBuildLog.split('\n'), event.message];
        _localBuildLog = lines.length > 120
            ? lines.sublist(lines.length - 120).join('\n')
            : lines.join('\n');
      });
    }, onError: (Object error) {
      if (mounted) setState(() => _localBuildLog = 'تعذر استقبال سجل البناء: $error');
    });
    String? staged;
    var buildSucceeded = false;
    try {
      staged = await _localBuildRunner.stageProject(projectUri, _projectName);
      if (!mounted) return;
      setState(() => _localBuildLog = 'اكتمل تجهيز المشروع. جارٍ تشغيل Flutter محليًا...');
      final buildMode = _localBuildMode;
      final apkPath = await _localBuildRunner.build(staged, mode: buildMode);
      final apkName = 'app-$buildMode.apk';
      await _localBuildRunner.saveArtifactToSaf(
        artifactPath: apkPath,
        parentUri: projectUri,
        fileName: apkName,
      );
      buildSucceeded = true;
      if (!mounted) return;
      _fullBuildLog.writeln('نجح البناء المحلي وحُفظ $apkName');
      setState(() => _localBuildLog = 'نجح البناء المحلي وحُفظ $apkName داخل مجلد المشروع.');
      _showMessage('اكتمل البناء المحلي وحُفظ $apkName.');
    } catch (error) {
      _fullBuildLog.writeln('فشل البناء المحلي: $error');
      if (!mounted) return;
      setState(() {
        final previous = _localBuildLog.trim();
        _localBuildLog = previous.isEmpty
            ? 'فشل البناء المحلي: $error'
            : '$previous\nفشل البناء المحلي: $error';
      });
      _showMessage('تعذر إكمال البناء المحلي: $error');
    } finally {
      if (staged != null) {
        try { await _localBuildRunner.removeStagedProject(staged); } catch (_) { /* best-effort cleanup */ }
      }
      await _recordBuildHistory(success: buildSucceeded);
      if (mounted) setState(() => _localBuildRunning = false);
      await _inspectLocalBuildEnvironment();
    }
  }

  Future<void> _cancelLocalBuild() async {
    try {
      await _localBuildRunner.cancel();
      if (mounted) setState(() => _localBuildLog = 'تم إرسال طلب إلغاء البناء.');
    } catch (error) {
      _showMessage('تعذر إلغاء البناء: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _installLocalBuildEngine() async {
    _engineUrlController.clear();
    _engineShaController.text = '8723baddc33fb92f033b142120add25d8ce7c037bd85a4af2b0cb4aba34dc8f8';
    String? selectedArchiveUri;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('تثبيت محرك البناء المحلي'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('يمكنك اختيار ملف GitHub الموجود على الهاتف Bisho-Flutter-Local-Engine-ARM64.zip مباشرة دون تنزيله أو فك الملف الداخلي يدويًا؛ سيقرأ التطبيق المحرك من داخله مباشرة. يمكنك أيضًا اختيار ZIP الداخلي أو استخدام رابط HTTPS مع بصمته الصحيحة.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final uri = await _engineInstaller.pickLocalArchive();
                  if (uri != null && dialogContext.mounted) {
                    updateDialog(() => selectedArchiveUri = uri);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('تعذر اختيار ملف المحرك: $error')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.folder_open),
              label: Text(selectedArchiveUri == null
                  ? 'اختيار ملف ZIP موجود على الهاتف'
                  : 'تم اختيار ملف ZIP محلي'),
            ),
            if (selectedArchiveUri != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('سيُقرأ الملف مباشرة دون نسخه إلى مساحة التطبيق.',
                  style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
              ),
            const SizedBox(height: 12),
            TextField(controller: _engineUrlController, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'رابط HTTPS (اختياري عند اختيار ملف محلي)', hintText: 'https://.../engine.zip')),
            const SizedBox(height: 8),
            TextField(controller: _engineShaController,
              decoration: const InputDecoration(labelText: 'SHA-256 للحزمة المحددة (64 خانة)', hintText: 'a1b2...')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(selectedArchiveUri == null ? 'تنزيل وتثبيت' : 'تثبيت الملف المحلي'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() { _engineInstalling = true; _localBuildLog = 'بدء تجهيز تثبيت محرك البناء...'; });
    await _engineInstallSubscription?.cancel();
    _engineInstallSubscription = _engineInstaller.progress.listen((event) {
      if (!mounted) return;
      final progress = event.fraction == null ? '' : ' ${(event.fraction! * 100).toStringAsFixed(1)}%';
      setState(() => _localBuildLog = '${event.message}$progress');
    });
    try {
      if (selectedArchiveUri != null) {
        await _engineInstaller.installFromUri(
          archiveUri: selectedArchiveUri!,
          sha256: _engineShaController.text,
        );
      } else {
        await _engineInstaller.install(
          archiveUrl: _engineUrlController.text,
          sha256: _engineShaController.text,
        );
      }
      _showMessage('تم تثبيت ملفات المحرك والتحقق من سلامة الحزمة.');
    } catch (error) {
      if (mounted) setState(() => _localBuildLog = 'فشل تثبيت المحرك: $error');
      _showMessage('تعذر تثبيت محرك البناء: $error');
    } finally {
      if (mounted) setState(() => _engineInstalling = false);
      await _inspectLocalBuildEnvironment();
    }
  }

  Future<void> _installAlpineRootfs() async {
    if (_alpineInstalling || _engineInstalling || _localBuildRunning || _probingLocalEngine) return;
    final free = _localBuildEnvironment?.availableBytes ?? 0;
    if (free < 1024 * 1024 * 1024) {
      _showMessage('يلزم توفر 1 GB على الأقل قبل تثبيت Alpine.');
      return;
    }
    setState(() {
      _alpineInstalling = true;
      _localBuildLog = 'بدء تنزيل Alpine ARM64 والتحقق من بصمته الرسمية...';
    });
    try {
      final result = await _alpineInstaller.install(onProgress: (message, received, total) {
        if (!mounted) return;
        final progress = total > 0 ? ' ${(received * 100 / total).clamp(0, 100).toStringAsFixed(1)}%' : '';
        setState(() => _localBuildLog = '$message$progress');
      });
      if (!mounted) return;
      setState(() => _localBuildLog = result['message']?.toString() ?? 'اكتمل تثبيت Alpine.');
      _showMessage('تم تثبيت Alpine والتحقق من ملفات النظام الأساسية.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _localBuildLog = 'فشل تثبيت Alpine: $error');
      _showMessage('تعذر تثبيت Alpine: $error');
    } finally {
      if (mounted) setState(() => _alpineInstalling = false);
      await _inspectLocalBuildEnvironment();
    }
  }

  Future<void> _cancelAlpineInstall() async {
    await _alpineInstaller.cancel();
    if (mounted) setState(() => _localBuildLog = 'تم طلب إلغاء تنزيل Alpine.');
  }

  Future<void> _probeLocalBuildEngine() async {
    if (_probingLocalEngine || _engineInstalling || _localBuildRunning) return;
    setState(() {
      _probingLocalEngine = true;
      _localBuildLog = 'جارٍ إنشاء مشروع Flutter تجريبي وبناء APK Debug حقيقي داخل المحرك؛ قد تستغرق العملية وقتًا...';
    });
    try {
      final result = await _localBuildService.probeEngine();
      final message = result['message']?.toString() ?? 'انتهى اختبار المحرك.';
      final log = result['log']?.toString() ?? '';
      if (mounted) {
        setState(() => _localBuildLog = log.isEmpty ? message : '$message\n$log');
        _showMessage(message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _localBuildLog = 'فشل اختبار المحرك: $error');
        _showMessage('فشل اختبار المحرك: $error');
      }
    } finally {
      if (mounted) setState(() => _probingLocalEngine = false);
      await _inspectLocalBuildEnvironment();
    }
  }

  Future<void> _inspectLocalBuildEnvironment() async {
    if (mounted) setState(() => _checkingLocalBuild = true);
    final environment = await _localBuildService.inspect();
    if (!mounted) return;
    setState(() {
      _localBuildEnvironment = environment;
      _checkingLocalBuild = false;
    });
  }

  Future<void> _checkProject() async {
    final uri = _projectUri;
    if (uri == null || uri.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isFlutterProject = false;
        _projectIssues = const [];
        _isFlutterSource = false;
        _hasAndroidPlatform = false;
        _projectMessage = 'لا يوجد مجلد مشروع مفتوح';
      });
      return;
    }
    setState(() {
      _checkingProject = true;
      _projectMessage = 'جارٍ فحص ملفات المشروع...';
    });
    try {
      final root = await widget.safFiles.getItem(uri);
      if (root == null || !root.isDir) {
        throw StateError('المجلد المحدد لم يعد متاحاً');
      }
      final children = await widget.safFiles.listDirectory(uri);
      final androidFolders = children.where((item) =>
          item.isDir && item.name.toLowerCase() == 'android').toList();
      final androidFolder = androidFolders.isEmpty ? null : androidFolders.first;
      final hasAndroidDirectory = androidFolder != null &&
          await _hasCompleteAndroidPlatform(androidFolder.uri);
      SafDocumentFile? pubspec;
      for (final item in children) {
        if (!item.isDir && item.name.toLowerCase() == 'pubspec.yaml') {
          pubspec = item;
          break;
        }
      }
      if (pubspec == null) {
        if (!mounted) return;
        setState(() {
          _isFlutterProject = false;
          _isFlutterSource = false;
          _hasAndroidPlatform = false;
          _projectIssues = const [];
          _projectMessage = 'المجلد لا يحتوي على pubspec.yaml؛ ليس جذر مشروع Flutter.';
        });
        return;
      }
      final content = utf8.decode(
        await widget.safFiles.readFile(pubspec.uri),
        allowMalformed: true,
      );
      // Parse YAML instead of searching text: comments or unrelated strings
      // must not make a non-Flutter folder pass the build preflight.
      final hasFlutterSdk =
          FlutterPubspecValidator.hasFlutterSdkDependency(content);
      final issues = hasFlutterSdk
          ? await ProjectScaffoldRepairService(widget.safFiles).inspectProject(uri)
          : const <ProjectHealthIssue>[];
      if (!mounted) return;
      setState(() {
        _projectIssues = issues;
        _isFlutterSource = hasFlutterSdk;
        _hasAndroidPlatform = hasAndroidDirectory;
        _isFlutterProject = hasFlutterSdk && hasAndroidDirectory;
        _projectMessage = !hasFlutterSdk
            ? 'تم العثور على pubspec.yaml، لكن لم يتم تأكيد اعتماد Flutter SDK.'
            : issues.isEmpty
                ? 'مشروع Flutter سليم بنيويًا وفق الفحوص المتاحة.'
                : 'تم العثور على ${issues.length} ملاحظة بنيوية؛ راجع التقرير أدناه.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isFlutterProject = false;
        _isFlutterSource = false;
        _hasAndroidPlatform = false;
        _projectIssues = const [];
        _projectMessage = 'تعذر فحص المشروع: $error';
      });
    } finally {
      if (mounted) setState(() => _checkingProject = false);
    }
  }

  Future<void> _repairProjectFiles() async {
    final uri = _projectUri;
    if (uri == null || uri.isEmpty || !_isFlutterSource || _repairingProject) return;
    setState(() => _repairingProject = true);
    try {
      final report = await ProjectScaffoldRepairService(widget.safFiles)
          .repairFlutterAndroid(
            projectRootUri: uri,
            projectName: _projectName,
            includeAndroid: _repairAndroidFiles,
            includeEntryPoint: _repairEntryPoint,
          );
      await _checkProject();
      if (!mounted) return;
      final message = StringBuffer()
        ..writeln('اكتملت عملية الفحص والإصلاح.')
        ..writeln('ملفات ومجلدات أُضيفت: ${report.created.length}')
        ..writeln('عناصر كانت موجودة: ${report.alreadyPresent.length}')
        ..writeln('الملاحظات قبل الإصلاح: ${report.beforeIssues.length}')
        ..writeln('الملاحظات بعد الإصلاح: ${report.afterIssues.length}');
      if (report.beforeIssues.isNotEmpty) {
        message.writeln('\nقبل الإصلاح:');
        for (final issue in report.beforeIssues) {
          message.writeln('- ${issue.path}: ${issue.message}');
        }
      }
      if (report.afterIssues.isNotEmpty) {
        message.writeln('\nما بقي بعد الإصلاح:');
        for (final issue in report.afterIssues) {
          message.writeln('- ${issue.path}: ${issue.message}');
        }
      }
      if (report.conflicts.isNotEmpty) {
        message.writeln('تعارضات تحتاج مراجعة: ${report.conflicts.length}');
        message.writeln(report.conflicts.join('\\n'));
      }
      if (report.created.isNotEmpty) {
        message.writeln('\\nالعناصر المضافة:\\n${report.created.join('\\n')}');
      }
      if (report.conflicts.isNotEmpty) {
        message.writeln('\\nلم يتم استبدال أي عنصر متعارض أو موجود مسبقًا.');
      }
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تقرير إصلاح المشروع'),
            content: SingleChildScrollView(child: SelectableText(message.toString())),
            actions: [TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسنًا'),
            )],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إكمال المشروع: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _repairingProject = false);
    }
  }

  Future<bool> _containsMainActivity(String directoryUri, {int depth = 0}) async {
    if (depth > 12) return false;
    final children = await widget.safFiles.listDirectory(directoryUri);
    for (final child in children) {
      if (child.isDir) {
        if (await _containsMainActivity(child.uri, depth: depth + 1)) return true;
      } else if (child.name == 'MainActivity.kt' ||
          child.name == 'MainActivity.java') {
        return true;
      }
    }
    return false;
  }

  Future<bool> _hasCompleteAndroidPlatform(String androidUri) async {
    try {
      final settings = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'settings.gradle',
      );
      final app = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'app',
      );
      final gradle = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'gradle',
      );
      if (settings == null || app == null || !app.isDir ||
          gradle == null || !gradle.isDir) return false;
      final appBuild = await widget.safFiles.findChild(
        parentUri: app.uri, name: 'build.gradle',
      );
      if (appBuild == null) return false;
      final src = await widget.safFiles.findChild(parentUri: app.uri, name: 'src');
      if (src == null || !src.isDir) return false;
      final main = await widget.safFiles.findChild(parentUri: src.uri, name: 'main');
      if (main == null || !main.isDir) return false;
      final manifest = await widget.safFiles.findChild(
        parentUri: main.uri, name: 'AndroidManifest.xml',
      );
      final res = await widget.safFiles.findChild(parentUri: main.uri, name: 'res');
      final kotlin = await widget.safFiles.findChild(parentUri: main.uri, name: 'kotlin');
      final java = await widget.safFiles.findChild(parentUri: main.uri, name: 'java');
      if (res == null || !res.isDir) return false;
      final hasKotlinActivity = kotlin != null && kotlin.isDir &&
          await _containsMainActivity(kotlin.uri);
      final hasJavaActivity = java != null && java.isDir &&
          await _containsMainActivity(java.uri);
      if (!hasKotlinActivity && !hasJavaActivity) return false;
      final values = await widget.safFiles.findChild(parentUri: res.uri, name: 'values');
      if (values == null || !values.isDir) return false;
      final styles = await widget.safFiles.findChild(parentUri: values.uri, name: 'styles.xml');
      final wrapper = await widget.safFiles.findChild(
        parentUri: gradle.uri, name: 'wrapper',
      );
      if (wrapper == null || !wrapper.isDir || manifest == null) return false;
      final wrapperJar = await widget.safFiles.findChild(
        parentUri: wrapper.uri, name: 'gradle-wrapper.jar',
      );
      final wrapperProperties = await widget.safFiles.findChild(
        parentUri: wrapper.uri, name: 'gradle-wrapper.properties',
      );
      final gradlew = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'gradlew',
      );
      final rootBuild = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'build.gradle',
      );
      final gradleProperties = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'gradle.properties',
      );
      final gradlewBat = await widget.safFiles.findChild(
        parentUri: androidUri, name: 'gradlew.bat',
      );
      return wrapperJar != null && !wrapperJar.isDir &&
          wrapperProperties != null && !wrapperProperties.isDir &&
          styles != null && !styles.isDir &&
          gradlew != null && !gradlew.isDir &&
          gradlewBat != null && !gradlewBat.isDir &&
          rootBuild != null && !rootBuild.isDir &&
          gradleProperties != null && !gradleProperties.isDir;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadGitHubSession() async {
    try {
      final token = await _githubService.readToken();
      if (token == null || token.isEmpty || !mounted) return;
      _tokenController.text = token;
      final account = await _githubService.verifyToken(token);
      if (!mounted) return;
      setState(() => _githubAccount = account);
    } catch (_) {
      if (!mounted) return;
      setState(() => _githubAccount = null);
    }
  }

  Future<void> _connectGitHub() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      final uri = Uri.parse('https://github.com/settings/tokens/new?scopes=repo,workflow&description=Bisho%20IDE');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _show('أنشئ Classic Personal Access Token بصلاحيات repo وworkflow ثم الصقه هنا.');
      return;
    }
    setState(() => _connectingGitHub = true);
    try {
      final account = await _githubService.verifyToken(token);
      await _githubService.saveToken(token);
      if (!mounted) return;
      setState(() => _githubAccount = account);
      _show('تم ربط حساب GitHub: ${account.login} وحفظ الاتصال بشكل آمن على الجهاز.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _githubAccount = null);
      _show('تعذر ربط GitHub: $error');
    } finally {
      if (mounted) setState(() => _connectingGitHub = false);
    }
  }

  Future<void> _disconnectGitHub() async {
    await _githubService.disconnect();
    if (!mounted) return;
    setState(() {
      _githubAccount = null;
      _tokenController.clear();
    });
    _show('تم فصل حساب GitHub وحذف الرمز المحفوظ من التخزين الآمن.');
  }

  Future<void> _createRepositoryAndBuild() async {
    if (!_isFlutterProject) {
      _show('افتح مجلد مشروع Flutter صحيحًا أولاً.');
      return;
    }
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _show('اربط حساب GitHub أولاً.');
      return;
    }
    final repoName = _repoController.text.trim().replaceAll(RegExp(r'^.*/'), '');
    if (repoName.isEmpty) {
      _show('أدخل اسم المستودع المطلوب إنشاؤه.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ إنشاء مستودع GitHub ورفع المشروع...';
      _log = 'بدء ربط المشروع بحساب GitHub.\n';
      _runUrl = null;
      _runId = null;
      _workflowStatus = null;
      _workflowConclusion = null;
    });
    try {
      final account = _githubAccount ?? await _githubService.verifyToken(token);
      await _githubService.saveToken(token);
      if (mounted) setState(() => _githubAccount = account);
      final result = await _githubService.createAndPushProject(
        token: token,
        projectUri: _projectUri!,
        repositoryName: repoName,
        description: 'Flutter project created with Bisho IDE',
        isPrivate: true,
        workflowFile: _workflowController.text.trim(),
        safFiles: widget.safFiles,
        onProgress: (message) {
          if (mounted) setState(() {
            _status = message;
            _log += '$message\n';
          });
        },
      );
      _repoController.text = '${result.owner}/${result.repository}';
      _branchController.text = result.branch;
      _workflowController.text = result.workflowFile;
      _dispatchTime = DateTime.now().toUtc();
      await _githubService.dispatchBuild(
        token: token,
        owner: result.owner,
        repository: result.repository,
        workflow: result.workflowFile,
        branch: result.branch,
        flutterVersion: _versionController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _status = 'تم إنشاء المستودع ورفع ${result.uploadedFiles} ملف وإرسال طلب البناء.';
        _log += '\nالمستودع: ${result.htmlUrl}\nالفرع: ${result.branch}\nعدد الملفات: ${result.uploadedFiles}\nتم إرسال workflow_dispatch بنجاح.';
        _runUrl = 'https://github.com/${result.owner}/${result.repository}/actions';
      });
      await _refreshBuildStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر إنشاء المستودع أو بدء البناء';
        _log += '\nالخطأ: $error\nتحقق من صلاحيات الرمز واسم المستودع واتصال الإنترنت.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer ${_tokenController.text.trim()}',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': 'application/json',
  };

  String get _repo => _repoController.text.trim().replaceAll(
    RegExp(r'^https?://github\.com/'), '',
  ).replaceAll(RegExp(r'\.git$'), '').replaceAll('/', '/');

  bool get _credentialsValid {
    final parts = _repo.split('/');
    return parts.length == 2 &&
        parts.every((part) => part.trim().isNotEmpty) &&
        _tokenController.text.trim().isNotEmpty &&
        _workflowController.text.trim().isNotEmpty &&
        _branchController.text.trim().isNotEmpty;
  }

  Future<void> _startRemoteBuild() async {
    if (!_isFlutterProject) {
      _show('افتح مجلد مشروع Flutter صحيحاً أولاً');
      return;
    }
    if (!_credentialsValid) {
      _show('أدخل المستودع بصيغة owner/repo وبيانات الاتصال المطلوبة');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ إرسال طلب البناء إلى GitHub...';
      _log = 'POST workflow_dispatch\nالمستودع: $_repo\nالفرع: ${_branchController.text.trim()}\n';
      _runUrl = null;
      _runId = null;
      _workflowStatus = null;
      _workflowConclusion = null;
      _dispatchTime = DateTime.now().toUtc();
    });
    try {
      final workflow = _workflowController.text.trim();
      final uri = Uri.https(
        'api.github.com',
        '/repos/$_repo/actions/workflows/${Uri.encodeComponent(workflow)}/dispatches',
      );
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'ref': _branchController.text.trim(),
          'inputs': {'flutter_version': _versionController.text.trim()},
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 204) {
        throw StateError(
          'GitHub رفض الطلب (${response.statusCode}): ${_safeBody(response.body)}',
        );
      }
      if (!mounted) return;
      setState(() {
        _status = 'تم قبول طلب البناء';
        _log += '\nGitHub API: HTTP 204\nتم إرسال workflow_dispatch بنجاح.\n'
            'سيتم العثور على رقم التشغيل عند تحديث الحالة.';
      });
      await _refreshBuildStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر بدء البناء';
        _log += '\nخطأ: $error\nتحقق من اسم المستودع والـ workflow والفرع وصلاحيات الرمز.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _safeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return body.length > 400 ? body.substring(0, 400) : body;
  }

  Future<void> _downloadBuildDiagnostics() async {
    final runId = int.tryParse(_runId ?? '');
    final repoParts = _repo.split('/');
    final token = _tokenController.text.trim();
    final projectUri = _projectUri;
    if (runId == null || repoParts.length != 2 || token.isEmpty || projectUri == null) {
      _show('لا توجد عملية بناء أو بيانات تنزيل تقرير صالحة.');
      return;
    }
    setState(() { _busy = true; _status = 'جارٍ تنزيل تقرير تشخيص GitHub Actions...'; });
    try {
      final bytes = await _githubService.downloadBuildDiagnostics(
        token: token, owner: repoParts[0], repository: repoParts[1], runId: runId,
      );
      final saved = await widget.safFiles.saveFile(
        parentUri: projectUri,
        fileName: 'bisho-build-diagnostics-$runId.zip',
        bytes: bytes,
        mimeType: 'application/zip',
        overwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _status = 'تم تنزيل تقرير التشخيص وحفظه داخل مجلد المشروع.';
        _log += '\nتقرير التشخيص: ${saved.name}\nالحجم: ${bytes.length} bytes';
      });
      _show('تم حفظ تقرير تشخيص البناء.');
    } catch (error) {
      if (!mounted) return;
      setState(() { _status = 'تعذر تنزيل تقرير التشخيص'; _log += '\n$error'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadRemoteApk() async {
    final runId = int.tryParse(_runId ?? '');
    final repoParts = _repo.split('/');
    final token = _tokenController.text.trim();
    final projectUri = _projectUri;
    if (runId == null || repoParts.length != 2 || token.isEmpty || projectUri == null) {
      _show('لا توجد عملية بناء مكتملة أو بيانات تنزيل صالحة.');
      return;
    }
    if (_workflowStatus != 'completed' || _workflowConclusion != 'success') {
      _show('لا يمكن تنزيل APK قبل نجاح عملية البناء.');
      return;
    }
    setState(() { _busy = true; _status = 'جارٍ تنزيل APK والتحقق من بصمة SHA-256...'; });
    try {
      final bytes = await _githubService.downloadReleaseApk(
        token: token,
        owner: repoParts[0],
        repository: repoParts[1],
        runId: runId,
      );
      final saved = await widget.safFiles.saveFile(
        parentUri: projectUri,
        fileName: 'app-release.apk',
        bytes: bytes,
        mimeType: 'application/vnd.android.package-archive',
        overwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _status = 'تم تنزيل APK والتحقق منه وحفظه داخل مجلد المشروع.';
        _log += '\nAPK: ${saved.name}\nالحجم: ${bytes.length} bytes\nSHA-256: اجتاز التحقق من ملف SHA256SUMS.txt.';
      });
      _show('تم حفظ app-release.apk داخل مجلد المشروع.');
    } catch (error) {
      if (!mounted) return;
      setState(() { _status = 'فشل تنزيل APK'; _log += '\n$error'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshBuildStatus() async {
    if (!_credentialsValid) {
      _show('أدخل بيانات GitHub أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ جلب حالة البناء...';
    });
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$_repo/actions/runs',
        {
          'branch': _branchController.text.trim(),
          'event': 'workflow_dispatch',
          'per_page': '10',
        },
      );
      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('GitHub API HTTP ${response.statusCode}: ${_safeBody(response.body)}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final runs = (payload['workflow_runs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      final since = _dispatchTime;
      final matching = runs.where((run) {
        final created = DateTime.tryParse(run['created_at']?.toString() ?? '');
        final correctWorkflow = (run['path']?.toString() ?? '')
            .endsWith(_workflowController.text.trim());
        final recentEnough = since == null || (created != null &&
            !created.isBefore(since.subtract(const Duration(minutes: 3))));
        return correctWorkflow && recentEnough;
      }).toList();
      if (matching.isEmpty) {
        if (!mounted) return;
        setState(() {
          _status = 'تم إرسال الطلب؛ ننتظر ظهور عملية البناء';
          _log += '\nلم تظهر العملية في قائمة GitHub بعد. أعد تحديث الحالة بعد قليل.';
        });
        return;
      }
      final run = matching.first;
      final status = run['status']?.toString() ?? 'unknown';
      final conclusion = run['conclusion']?.toString();
      if (!mounted) return;
      setState(() {
        _runId = run['id']?.toString();
        _runUrl = run['html_url']?.toString();
        _workflowStatus = status;
        _workflowConclusion = conclusion;
        _status = status == 'completed'
            ? 'انتهى البناء: ${_conclusionArabic(conclusion)}'
            : 'البناء قيد التنفيذ: ${_statusArabic(status)}';
        _log = 'Workflow: ${_workflowController.text.trim()}\n'
            'Run ID: ${_runId ?? '-'}\n'
            'الحالة: ${_statusArabic(status)}\n'
            'النتيجة: ${_conclusionArabic(conclusion)}\n'
            'Commit: ${run['head_sha'] ?? '-'}\n'
            'الفرع: ${run['head_branch'] ?? '-'}\n'
            'تاريخ الإنشاء: ${run['created_at'] ?? '-'}\n'
            'رابط التشغيل: ${_runUrl ?? '-'}\n';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر تحديث الحالة';
        _log = 'خطأ في قراءة GitHub Actions:\n$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusArabic(String? status) {
    switch (status) {
      case 'queued': return 'في قائمة الانتظار';
      case 'in_progress': return 'قيد التنفيذ';
      case 'completed': return 'مكتمل';
      default: return status ?? 'غير معروف';
    }
  }

  String _conclusionArabic(String? value) {
    switch (value) {
      case 'success': return 'نجاح';
      case 'failure': return 'فشل';
      case 'cancelled': return 'أُلغي';
      case 'timed_out': return 'انتهت المهلة';
      case null: return 'لم تنتهِ بعد';
      default: return value;
    }
  }

  Future<void> _openRun() async {
    final value = _runUrl;
    if (value == null) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log));
    _show('تم نسخ سجل البناء');
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _field(String label, TextEditingController controller, {
    String? hint, bool secret = false, ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFF080D19),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF26334D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF26334D)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, color: _cyan, size: 17),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      )),
    ]),
  );

  Widget _localBuildInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 116, child: Text(label,
        style: const TextStyle(color: _muted, fontSize: 11))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _panel({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _panelColor,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF26334D)),
      boxShadow: const [
        BoxShadow(color: Color(0x2200B8FF), blurRadius: 18, spreadRadius: -10),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final success = _workflowConclusion == 'success';
    final failed = _workflowConclusion == 'failure';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B2D),
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: Color(0xFF26374E))),
          title: const Text('بناء ومعاينة Flutter',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          actions: [
            IconButton(onPressed: _copyLog, icon: const Icon(Icons.copy_rounded),
              tooltip: 'نسخ سجل البناء'),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _panel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.folder_special_rounded, color: _cyan),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('فحص المشروع',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  if (_checkingProject)
                    const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 12),
                Text(_projectName, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_isFlutterProject ? Icons.check_circle : Icons.info_outline,
                    color: _isFlutterProject ? Colors.greenAccent : Colors.orangeAccent,
                    size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_projectMessage,
                    style: const TextStyle(color: _muted, height: 1.4, fontSize: 12))),
                ]),
                if (_projectIssues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ملاحظات الفحص (${_projectIssues.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        ..._projectIssues.take(8).map((issue) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• ${issue.path}: ${issue.message}',
                            style: const TextStyle(color: _muted, fontSize: 11)),
                        )),
                        if (_projectIssues.length > 8)
                          Text('و ${_projectIssues.length - 8} ملاحظات أخرى',
                            style: const TextStyle(color: _muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () async {
                    await widget.onPickProject();
                    _projectUri = widget.projectUriProvider();
                    _projectName = widget.projectNameProvider();
                    _repoController.text = _projectName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
                    await _checkProject();
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('اختيار مجلد مشروع'),
                ),
                if (_isFlutterSource && (!_hasAndroidPlatform || _projectIssues.any((issue) => issue.repairable))) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    value: _repairAndroidFiles,
                    onChanged: _repairingProject ? null : (value) => setState(() => _repairAndroidFiles = value ?? false),
                    title: const Text('إصلاح ملفات Android وGradle الناقصة', style: TextStyle(fontSize: 12)),
                  ),
                  CheckboxListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    value: _repairEntryPoint,
                    onChanged: _repairingProject ? null : (value) => setState(() => _repairEntryPoint = value ?? false),
                    title: const Text('استعادة lib/main.dart إذا كان مفقودًا', style: TextStyle(fontSize: 12)),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || _repairingProject || (!_repairAndroidFiles && !_repairEntryPoint) ? null : _repairProjectFiles,
                      icon: _repairingProject
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.build_circle_outlined),
                      label: Text(_repairingProject
                          ? 'جارٍ إصلاح المشروع...'
                          : 'إصلاح المشروع بالكامل'),
                    ),
                  ),
                ],
              ],
            )),
            const SizedBox(height: 12),
            _panel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.memory_rounded, color: _cyan),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('البناء المحلي داخل Bisho IDE',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  if (_checkingLocalBuild)
                    const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 8),
                Text(
                  _localBuildEnvironment?.message ?? 'جارٍ فحص بيئة البناء المحلية...',
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 10),
                if (_localBuildEnvironment != null) ...[
                  _sectionHeading('حالة الجهاز والمحرك', Icons.fact_check_rounded),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1728),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFF26374E)),
                    ),
                    child: Column(children: [
                      _localBuildInfoRow('معمارية الهاتف', _localBuildEnvironment!.deviceAbi),
                      _localBuildInfoRow('إصدار Android API', _localBuildEnvironment!.androidVersion == 0
                          ? 'غير متاح' : _localBuildEnvironment!.androidVersion.toString()),
                      _localBuildInfoRow('المساحة الحرة', _localBuildEnvironment!.availableStorageLabel),
                      _localBuildInfoRow('دعم الجهاز', _localBuildEnvironment!.deviceSupported
                          ? 'يحقق المتطلبات الأولية' : 'لا يحقق المتطلبات الأولية'),
                      _localBuildInfoRow('المساحة المطلوبة', _localBuildEnvironment!.requiredStorageLabel),
                      const Divider(height: 14, color: Color(0xFF26374E)),
                      _localBuildInfoRow('نظام Alpine ARM64', _localBuildEnvironment!.alpineRootfsInstalled
                          ? 'مثبّت وموجود' : 'غير مثبّت'),
                      _localBuildInfoRow('ملفات المحرك', _localBuildEnvironment!.engineInstalled
                          ? 'موجودة بنيويًا' : 'غير مكتملة'),
                      _localBuildInfoRow('اختبار Debug APK', _localBuildEnvironment!.debugBuildVerified
                          ? 'نجح البناء والتحقق من التوقيع والمحاذاة' : 'لم ينجح بعد'),
                      _localBuildInfoRow('اختبار Release/AOT', _localBuildEnvironment!.releaseBuildVerified
                          ? 'تم إنتاج APK والتحقق من توقيعه' : 'لم ينجح بعد؛ Debug لا يكفي لاعتماده'),
                      if (_localBuildEnvironment!.missingRequirements.isNotEmpty) ...[
                        const Divider(height: 14, color: Color(0xFF26374E)),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text('النواقص والمتطلبات',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent, fontSize: 12)),
                        ),
                        ..._localBuildEnvironment!.missingRequirements.map((item) =>
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 15),
                              const SizedBox(width: 6),
                              Expanded(child: Text(item,
                                style: const TextStyle(color: _muted, fontSize: 11, height: 1.4))),
                            ]),
                          )),
                      ],
                    ]),
                  ),
                ],
                if (_localBuildEnvironment != null) ...[
                  const SizedBox(height: 12),
                  _sectionHeading('تقرير صحة المحرك — فحص آمن', Icons.health_and_safety_rounded),
                  Builder(builder: (context) {
                    final report = EngineHealthReport.fromEnvironment(_localBuildEnvironment!);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1424),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF26374E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.headline,
                            style: TextStyle(
                              color: report.failed > 0 ? Colors.orangeAccent : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            )),
                          const SizedBox(height: 5),
                          Text('ناجح: ${report.passed}  •  تنبيه: ${report.warnings}  •  يحتاج معالجة: ${report.failed}',
                            style: const TextStyle(color: _muted, fontSize: 10)),
                          const Divider(height: 16, color: Color(0xFF26374E)),
                          ...report.checks.map((check) {
                            final passed = check.state == EngineCheckState.passed;
                            final failed = check.state == EngineCheckState.failed;
                            final color = passed ? Colors.greenAccent :
                                failed ? Colors.redAccent : Colors.orangeAccent;
                            final icon = passed ? Icons.check_circle_rounded :
                                failed ? Icons.error_rounded : Icons.info_rounded;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, color: color, size: 15),
                                  const SizedBox(width: 7),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(check.title, style: const TextStyle(
                                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                      Text(check.detail, style: const TextStyle(
                                        color: _muted, fontSize: 10, height: 1.35)),
                                    ],
                                  )),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 5),
                          const Text(
                            'هذا التقرير لا يغيّر ملفات المحرك ولا يحذف النسخ السابقة. فحوص البناء غير المجراة تبقى غير معتمدة.',
                            style: TextStyle(color: _muted, fontSize: 10, height: 1.4),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'اختبار المحرك ينشئ مشروع Flutter مؤقتًا ويبني APK Debug حقيقيًا؛ قد يستغرق حتى 60 دقيقة عند تنزيل Gradle ومكونات Android لأول مرة.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionHeading('تجهيز بيئة Linux', Icons.inventory_2_outlined),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _alpineInstalling || _engineInstalling || _localBuildRunning || _probingLocalEngine || _checkingLocalBuild
                        ? null : _installAlpineRootfs,
                    icon: _alpineInstalling
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.archive_outlined),
                    label: Text(_alpineInstalling ? 'جارٍ تنزيل واستخراج Alpine...' : 'تثبيت Alpine ARM64 داخل التطبيق'),
                  ),
                ),
                if (_alpineInstalling)
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(
                    onPressed: _cancelAlpineInstall,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('إلغاء تثبيت Alpine'),
                  )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _engineInstalling || _alpineInstalling || _localBuildRunning || _probingLocalEngine || _checkingLocalBuild ||
                        !(_localBuildEnvironment?.engineInstalled == true)
                        ? null : _probeLocalBuildEngine,
                    icon: _probingLocalEngine
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.health_and_safety_outlined),
                    label: Text(_probingLocalEngine ? 'جارٍ اختبار المحرك...' : 'اختبار بناء APK تجريبي فعليًا'),
                  ),
                ),
                const SizedBox(height: 14),
                _sectionHeading('اختبار وإدارة المحرك', Icons.build_circle_outlined),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _engineInstalling || _alpineInstalling || _localBuildRunning || _probingLocalEngine || _checkingLocalBuild ||
                        !(_localBuildEnvironment?.deviceSupported == true)
                        ? null : _installLocalBuildEngine,
                    icon: _engineInstalling
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.downloading_rounded),
                    label: Text(_engineInstalling ? 'جارٍ تنزيل/تثبيت المحرك...' : 'تثبيت محرك البناء من حزمة موثوقة'),
                  ),
                ),
                if (_engineInstaller.canCancel)
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(
                    onPressed: () async {
                      await _engineInstaller.cancel();
                      if (mounted) setState(() => _localBuildLog = 'تم طلب إيقاف التنزيل.');
                    },
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('إلغاء تنزيل المحرك'),
                  )),
                const SizedBox(height: 14),
                _sectionHeading('إعدادات البناء المحلي', Icons.tune_rounded),
                DropdownButtonFormField<String>(
                  initialValue: _localBuildMode,
                  decoration: const InputDecoration(
                    labelText: 'نوع ملف APK المحلي',
                    helperText: 'Debug مناسب لاختبار البناء على ARM64؛ Release يحتاج أدوات AOT متوافقة.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'debug', child: Text('Debug APK — للاختبار')),
                    DropdownMenuItem(value: 'release', child: Text('Release APK — يتطلب AOT ARM64')),
                  ],
                  onChanged: _localBuildRunning ? null : (value) {
                    if (value != null) _setLocalBuildMode(value);
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _localBuildRunning || _probingLocalEngine || _checkingLocalBuild ||
                        !(_localBuildEnvironment?.deviceSupported == true &&
                          _localBuildEnvironment?.engineInstalled == true)
                        ? null : _startLocalBuild,
                    icon: _localBuildRunning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.build_circle_outlined),
                    label: Text(_localBuildRunning ? 'جارٍ البناء محليًا...' : 'بناء APK محليًا داخل التطبيق'),
                  ),
                ),
                if (_localBuildRunning)
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(
                    onPressed: _cancelLocalBuild,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('إلغاء البناء'),
                  )),
                if (_localBuildLog.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _sectionHeading('سجل العمليات', Icons.receipt_long_rounded),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(child: SelectableText(_localBuildLog,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70))),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _openBuildAnalysis,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('تحليل السجل والأخطاء وعمليات البناء السابقة'),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _checkingLocalBuild ? null : _inspectLocalBuildEnvironment,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('فحص صحة المحرك الآن (قراءة فقط)'),
                  ),
                ),
                const Text(
                  'يعمل البناء المحلي فقط عند تثبيت محرك Linux المدمج المتوافق. يقوم التطبيق بترحيل المشروع لمساحته الخاصة ثم يشغّل Flutter عبر المحرك، ويحفظ APK في مجلد المشروع. لم يُثبت نجاحه على جهازك بعد؛ البناء عبر GitHub أدناه سحابي.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.5),
                ),
              ],
            )),
            const SizedBox(height: 12),
            _panel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.cloud_sync_rounded, color: _cyan),
                  SizedBox(width: 9),
                  Expanded(child: Text('البناء السحابي عبر GitHub Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'يمكن للتطبيق إنشاء مستودع خاص تلقائيًا، ورفع ملفات المشروع المحلية كاملة، ثم تشغيل GitHub Actions. كما يمكنك استخدام مستودع موجود يدويًا.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 14),
                _sectionHeading('اتصال GitHub الآمن', Icons.verified_user_rounded),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1728),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF26374E)),
                  ),
                  child: Row(children: [
                  Icon(_githubAccount == null ? Icons.link_off : Icons.verified_user,
                    color: _githubAccount == null ? Colors.orangeAccent : Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _githubAccount == null ? 'حساب GitHub غير مربوط' : 'متصل: ${_githubAccount!.login}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )),
                  if (_githubAccount != null)
                    IconButton(onPressed: _busy ? null : _disconnectGitHub,
                      tooltip: 'فصل الحساب', icon: const Icon(Icons.logout_rounded)),
                  ]),
                ),
                const SizedBox(height: 8),
                _field('رمز GitHub الشخصي (PAT)', _tokenController,
                  hint: 'الصق الرمز ثم اضغط ربط الحساب', secret: true),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy || _connectingGitHub ? null : _connectGitHub,
                    icon: _connectingGitHub
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_rounded),
                    label: Text(_connectingGitHub ? 'جارٍ التحقق...' : 'ربط حساب GitHub / حفظ الاتصال'),
                  ),
                ),
                const Text(
                  'استخدم Classic Personal Access Token مع تحديد repo وworkflow. يُخزّن الرمز في Android Keystore عبر التخزين الآمن، ولا يُكتب في سجل البناء. لا ترسل الرمز لأي شخص.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 16),
                _sectionHeading('إعدادات المستودع والبناء', Icons.settings_ethernet_rounded),
                _field('اسم المستودع الجديد / أو owner/repo للبناء اليدوي', _repoController, hint: 'my-flutter-app', onChanged: (_) => _saveRemoteBuildSettings()),
                _field('ملف Workflow', _workflowController, hint: 'build-android.yml أو main.yml', onChanged: (_) => _saveRemoteBuildSettings()),
                Row(children: [
                  Expanded(child: _field('الفرع', _branchController, hint: 'main', onChanged: (_) => _saveRemoteBuildSettings())),
                  const SizedBox(width: 8),
                  Expanded(child: _field('إصدار Flutter', _versionController, onChanged: (_) => _saveRemoteBuildSettings())),
                ]),
                const SizedBox(height: 14),
                _sectionHeading('تشغيل وإدارة البناء السحابي', Icons.rocket_launch_rounded),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _createRepositoryAndBuild,
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: Text(_busy ? 'جارٍ إنشاء المستودع والرفع...' : 'إنشاء مستودع تلقائيًا ورفع المشروع وبدء البناء'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _startRemoteBuild,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('بناء مستودع موجود يدويًا'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _refreshBuildStatus,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث حالة البناء'),
                  ),
                ),
              ],
            )),
            const SizedBox(height: 12),
            _panel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(success ? Icons.check_circle : failed ? Icons.error : Icons.timelapse,
                    color: success ? Colors.greenAccent : failed ? Colors.redAccent : _cyan),
                  const SizedBox(width: 8),
                  const Text('حالة العملية',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: success ? const Color(0xFF0D2B25)
                        : failed ? const Color(0xFF321A24) : const Color(0xFF0C1728),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: success ? const Color(0xFF167A5B)
                        : failed ? const Color(0xFF8D3448) : const Color(0xFF26374E)),
                  ),
                  child: Row(children: [
                    Icon(success ? Icons.check_circle_rounded
                        : failed ? Icons.error_rounded : Icons.hourglass_top_rounded,
                      color: success ? Colors.greenAccent : failed ? Colors.redAccent : _cyan),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_status,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  ]),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 100, maxHeight: 230),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF080D19),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(_log,
                      style: const TextStyle(fontFamily: 'monospace',
                        fontSize: 11, color: Colors.white70, height: 1.5)),
                  ),
                ),
                if (_runId != null) ...[
                  const SizedBox(height: 10),
                  Text('Run ID: $_runId',
                    style: const TextStyle(color: _muted, fontSize: 11)),
                ],
                if (_runUrl != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openRun,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('فتح تفاصيل البناء وتنزيل APK'),
                    )),
                ],
                if (_runId != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _downloadBuildDiagnostics,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('تنزيل تقرير التشخيص (حتى عند فشل البناء)'),
                    )),
                ],
                if (success) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _downloadRemoteApk,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('تنزيل APK إلى مجلد المشروع'),
                    )),
                ],
                if (success)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('اكتمل البناء بنجاح. يمكنك تنزيل APK مباشرةً إلى مجلد المشروع من الزر أعلاه.',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ),
              ],
            )),
            const SizedBox(height: 12),
            _panel(child: const Text(
              'مهم: شاشة المعاينة لا تشغّل APK داخل التطبيق. هي تتحقق من مشروع Flutter '
              'وتدير طلب بناء سحابي حقيقي. معاينة واجهة التطبيق على الجهاز تتطلب تشغيل '
              'التطبيق الناتج أو ربط جهاز/محاكي ببيئة Flutter.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
            )),
          ],
        ),
      ),
    );
  }
}
