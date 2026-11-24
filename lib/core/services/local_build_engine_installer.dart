import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class EngineInstallProgress {
  const EngineInstallProgress(this.message, {this.received = 0, this.total = 0});
  final String message;
  final int received;
  final int total;
  double? get fraction => total > 0 ? (received / total).clamp(0, 1).toDouble() : null;
}

/// Streams a user-supplied HTTPS archive to disk; Android verifies its SHA-256
/// and performs bounded, zip-slip-safe extraction before atomically installing it.
class LocalBuildEngineInstaller {
  static const _channel = MethodChannel('com.bisho.ide/local_build');
  final _controller = StreamController<EngineInstallProgress>.broadcast();
  Stream<EngineInstallProgress> get progress => _controller.stream;
  bool _cancelled = false;
  bool _installing = false;
  bool _downloadActive = false;
  bool _nativeInstallStarted = false;
  HttpClient? _client;

  void _report(EngineInstallProgress event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Cancellation is available only while the HTTPS archive is downloading.
  /// Android extraction runs in a native worker and is intentionally not
  /// presented as cancellable once that phase has started.
  bool get canCancel => _downloadActive && !_nativeInstallStarted;

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> dispose() async {
    if (canCancel) await cancel();
    await _controller.close();
  }

  String _formatBytes(int value) => '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  /// Automatically run the full on-device PRoot + Flutter APK smoke test.
  /// Native code keeps the previous engine until this test passes and rolls
  /// back automatically on any failure.
  Future<void> _verifyInstalledEngine() async {
    _report(const EngineInstallProgress(
      'اكتمل الاستخراج الآمن. جارٍ اختبار PRoot وبناء APK تجريبي على هذا الهاتف قبل اعتماد المحرك...',
    ));
    final result = await _channel.invokeMapMethod<Object?, Object?>('probeEngine');
    if (result?['success'] != true || result?['activated'] != true) {
      throw StateError(
        result?['message']?.toString() ??
            'لم يجتز المحرك اختبار التشغيل الفعلي؛ لم يتم اعتماده.',
      );
    }
    _report(const EngineInstallProgress(
      'نجح اختبار PRoot وبناء APK وتثبيته وتشغيله؛ تم اعتماد المحرك تلقائياً.',
    ));
  }

  Future<void> install({required String archiveUrl, required String sha256}) async {
    final uri = Uri.tryParse(archiveUrl.trim());
    final digest = sha256.trim().toLowerCase();
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw ArgumentError('يجب إدخال رابط HTTPS مباشر وموثوق لحزمة المحرك.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw ArgumentError('قيمة SHA-256 يجب أن تتكون من 64 خانة hex.');
    }
    if (_installing) throw StateError('هناك عملية تثبيت لمحرك البناء قيد التنفيذ بالفعل.');
    _installing = true;
    _cancelled = false;
    late final File archive;
    try {
      final environment = await _channel.invokeMapMethod<Object?, Object?>('inspectEnvironment');
      final available = (environment?['availableBytes'] as num?)?.toInt() ?? 0;
      final requiredReserve = (environment?['engineInstallStorageBytes'] as num?)?.toInt() ??
          1024 * 1024 * 1024;
      if (available < requiredReserve) {
        throw StateError('يلزم توفر ${_formatBytes(requiredReserve)} كمساحة احتياطية قبل تنزيل المحرك.');
      }
      final support = await getApplicationSupportDirectory();
      final downloadDir = Directory('${support.path}/bisho-engine-downloads');
      await downloadDir.create(recursive: true);
      archive = File('${downloadDir.path}/engine-${DateTime.now().microsecondsSinceEpoch}.zip');
    } catch (_) {
      _installing = false;
      rethrow;
    }
    IOSink? sink;
    try {
      _downloadActive = true;
      _report(const EngineInstallProgress('جارٍ الاتصال بمصدر حزمة المحرك...'));
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final request = await _client!.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/zip, application/octet-stream');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('استجاب الخادم برمز HTTP ${response.statusCode}.');
      }
      final total = response.contentLength;
      if (total <= 0 || total > 8 * 1024 * 1024 * 1024) {
        throw StateError('حجم الحزمة غير معروف أو يتجاوز الحد المسموح (8 GB).');
      }
      final current = await _channel.invokeMapMethod<Object?, Object?>('inspectEnvironment');
      final freeAfterArchive = (current?['availableBytes'] as num?)?.toInt() ?? 0;
      if (freeAfterArchive < total + 1024 * 1024 * 1024) {
        throw StateError('المساحة لا تكفي لهذه الحزمة: يلزم ${_formatBytes(total)} للتنزيل إضافة إلى 1 GB احتياطي. اختر حزمة أصغر أو وفر مساحة.');
      }
      sink = archive.openWrite();
      var received = 0;
      var lastReport = DateTime.now();
      await for (final chunk in response) {
        if (_cancelled) throw StateError('أُلغي تنزيل محرك البناء.');
        received += chunk.length;
        if (received > total || received > 8 * 1024 * 1024 * 1024) {
          throw StateError('تجاوز التنزيل الحجم المعلن؛ أُوقف لحماية مساحة الجهاز.');
        }
        sink.add(chunk);
        if (DateTime.now().difference(lastReport).inMilliseconds >= 350) {
          _report(EngineInstallProgress('جارٍ تنزيل حزمة المحرك...', received: received, total: total));
          lastReport = DateTime.now();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != total) throw StateError('اكتمل الاتصال بحجم غير مطابق للحجم المعلن.');
      if (_cancelled) throw StateError('أُلغي تثبيت محرك البناء.');
      _downloadActive = false;
      _nativeInstallStarted = true;
      _report(const EngineInstallProgress('تم التنزيل. جارٍ التحقق من SHA-256 وفك الحزمة بأمان؛ لا يمكن إلغاء هذه المرحلة...'));
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'installEngine', {'archivePath': archive.path, 'sha256': digest},
      );
      if (result?['success'] != true) {
        throw StateError(result?['message']?.toString() ?? 'رفض Android تثبيت حزمة المحرك.');
      }
      await _verifyInstalledEngine();
    } finally {
      _installing = false;
      _downloadActive = false;
      _nativeInstallStarted = false;
      try { await sink?.close(); } catch (_) {}
      _client?.close(force: true);
      _client = null;
      if (await archive.exists()) await archive.delete();
    }
  }

  /// Opens Android's document picker and returns a content:// URI without copying the selected archive.
  Future<String?> pickLocalArchive() async {
    return _channel.invokeMethod<String>('pickEngineArchive');
  }

  /// Installs an already-downloaded ZIP directly from its SAF URI; no HTTPS download or cache copy is made.
  Future<void> installFromUri({required String archiveUri, required String sha256}) async {
    final uri = Uri.tryParse(archiveUri.trim());
    final digest = sha256.trim().toLowerCase();
    if (uri == null || uri.scheme != 'content') {
      throw ArgumentError('اختر ملف ZIP من منتقي ملفات Android.');
    }
    final validDigest = digest.length == 64 && digest.codeUnits.every((code) =>
        (code >= 48 && code <= 57) || (code >= 97 && code <= 102));
    if (!validDigest) {
      throw ArgumentError('قيمة SHA-256 يجب أن تتكون من 64 خانة hex.');
    }
    if (_installing) throw StateError('هناك عملية تثبيت لمحرك البناء قيد التنفيذ بالفعل.');
    _installing = true;
    _cancelled = false;
    _nativeInstallStarted = true;
    try {
      _report(const EngineInstallProgress('تم اختيار الملف المحلي. جارٍ التحقق من SHA-256 واستخراج المحرك مباشرة دون نسخة مؤقتة...'));
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'installEngineFromUri',
        {'archiveUri': uri.toString(), 'sha256': digest},
      );
      if (result?['success'] != true) {
        throw StateError(result?['message']?.toString() ?? 'رفض Android تثبيت ملف المحرك المحلي.');
      }
      await _verifyInstalledEngine();
    } finally {
      _installing = false;
      _nativeInstallStarted = false;
    }
  }

}
