import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads the pinned official Alpine minirootfs and verifies the official
/// SHA-256 sidecar before native, bounded TAR.GZ extraction.
class AlpineRootfsInstaller {
  static const _channel = MethodChannel('com.bisho.ide/local_build');
  static const archiveUrl = 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-3.24.4-aarch64.tar.gz';
  static const checksumUrl = '$archiveUrl.sha256';
  static const release = '3.24.4';
  bool _cancelled = false;
  HttpClient? _client;

  Future<void> cancel() async {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<Map<Object?, Object?>> install({void Function(String message, int received, int total)? onProgress}) async {
    _cancelled = false;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/bisho-engine-downloads');
    await directory.create(recursive: true);
    final archive = File('${directory.path}/alpine-$release-aarch64.tar.gz');
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      onProgress?.call('جلب بصمة Alpine الرسمية...', 0, 0);
      final checksumText = await _getText(checksumUrl);
      final digest = _parseSha256(checksumText, 'alpine-minirootfs-3.24.4-aarch64.tar.gz');
      onProgress?.call('تنزيل Alpine $release...', 0, 0);
      await _download(archiveUrl, archive, onProgress);
      if (_cancelled) throw StateError('تم إلغاء تنزيل Alpine.');
      onProgress?.call('التحقق من SHA-256 واستخراج TAR.GZ بأمان...', archive.lengthSync(), archive.lengthSync());
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'installAlpineRootfs', {'archivePath': archive.path, 'sha256': digest},
      );
      if (result?['success'] != true) {
        throw StateError(result?['message']?.toString() ?? 'فشل تثبيت Alpine داخل التطبيق.');
      }
      return result!;
    } finally {
      _client?.close(force: true);
      _client = null;
      if (await archive.exists()) await archive.delete();
    }
  }

  Future<String> _getText(String url) async {
    final uri = Uri.parse(url);
    final request = await _client!.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) throw HttpException('تعذر جلب بصمة Alpine الرسمية: HTTP ${response.statusCode}.');
    if (response.contentLength > 16 * 1024) throw const FormatException('ملف البصمة أكبر من المتوقع.');
    return utf8.decode(await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)));
  }

  String _parseSha256(String text, String expectedName) {
    final matches = RegExp(r'^\s*([a-fA-F0-9]{64})\s+\*?([^\s]+)\s*$', multiLine: true)
        .allMatches(text).where((m) => m.group(2) == expectedName).toList();
    if (matches.length != 1) throw const FormatException('ملف SHA-256 الرسمي لا يحتوي بصمة وحيدة مطابقة لاسم الأرشيف.');
    return matches.single.group(1)!.toLowerCase();
  }

  Future<void> _download(String url, File destination,
      void Function(String, int, int)? onProgress) async {
    final request = await _client!.getUrl(Uri.parse(url));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/gzip, application/octet-stream');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) throw HttpException('تعذر تنزيل Alpine: HTTP ${response.statusCode}.');
    final total = response.contentLength;
    if (total <= 0 || total > 256 * 1024 * 1024) throw StateError('حجم أرشيف Alpine غير معروف أو يتجاوز 256 MB.');
    if (!await destination.parent.exists()) throw StateError('مجلد تنزيل Alpine غير متاح.');
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response) {
        if (_cancelled) throw StateError('تم إلغاء تنزيل Alpine.');
        received += chunk.length;
        if (received > total) throw StateError('تجاوز تنزيل Alpine الحجم المعلن.');
        sink.add(chunk);
        onProgress?.call('تنزيل Alpine...', received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received != total) throw StateError('حجم تنزيل Alpine لا يطابق Content-Length.');
  }
}
