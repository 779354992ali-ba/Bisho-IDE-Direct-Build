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
  static const _maxRedirects = 5;
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

  Future<HttpClientResponse> _openArchiveResponse(Uri initialUri) async {
    var currentUri = initialUri;
    final visited = <Uri>{};
    for (var redirects = 0; ; redirects++) {
      if (!visited.add(currentUri)) {
        throw const HttpException('اكتُشفت حلقة تحويل أثناء تنزيل حزمة المحرك.');
      }
      final request = await _client!.getUrl(currentUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/zip, application/octet-stream');
      final response = await request.close();
      final status = response.statusCode;
      final isRedirect = status == HttpStatus.movedPermanently ||
          status == HttpStatus.found ||
          status == HttpStatus.seeOther ||
          status == HttpStatus.temporaryRedirect ||
          status == HttpStatus.permanentRedirect;
      if (!isRedirect) return response;
      if (redirects >= _maxRedirects) {
        await response.drain<void>();
        throw const HttpException('تجاوز رابط الحزمة الحد الأقصى لتحويلات HTTPS.');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        await response.drain<void>();
        throw const HttpException('أعاد خادم الحزمة تحويلاً بلا عنوان وجهة.');
      }
      final nextUri = currentUri.resolve(location.trim());
      await response.drain<void>();
      if (nextUri.scheme.toLowerCase() != 'https' ||
          nextUri.host.isEmpty ||
          nextUri.userInfo.isNotEmpty ||
          nextUri.hasFragment) {
        throw const HttpException('رُفض تحويل تنزيل الحزمة لأنه لا يستخدم HTTPS آمناً.');
      }
      currentUri = nextUri;
    }
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
      // GitHub Releases and object-storage CDNs commonly redirect downloads.
      // Follow a small, loop-safe chain, but never permit an HTTPS downgrade.
      final response = await _openArchiveResponse(uri);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('استجاب الخادم برمز HTTP ${response.statusCode}.');
      }
      final total = response.contentLength;
      if (total <= 0 || total > 8 * 1024 * 1024 * 1024) {
        await response.drain<void>();
        throw StateError('حجم الحزمة غير معروف أو يتجاوز الحد المسموح (8 GB).');
      }
      final current = await _channel.invokeMapMethod<Object?, Object?>('inspectEnvironment');
      final freeAfterArchive = (current?['availableBytes'] as num?)?.toInt() ?? 0;
      if (freeAfterArchive < total + 1024 * 1024 * 1024) {
        await response.drain<void>();
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
      _report(const EngineInstallProgress('اكتمل تثبيت ملفات المحرك. يلزم اختبار بناء APK فعلي قبل تفعيله.'));
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
}
