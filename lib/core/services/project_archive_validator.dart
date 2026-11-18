/// Validation helpers for ZIP project import.
///
/// Limits protect the editor from malformed paths and oversized archives.
class ProjectArchiveValidator {
  ProjectArchiveValidator._();

  static const int maxEntries = 10000;
  static const int maxSingleFileBytes = 64 * 1024 * 1024;
  static const int maxTotalBytes = 256 * 1024 * 1024;

  static String normalizePath(String input) {
    if (input.isEmpty || input.contains('\u0000')) {
      throw FormatException('مسار فارغ أو يحتوي على محرف غير صالح');
    }
    final path = input.replaceAll('\\', '/');
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      throw FormatException('المسارات المطلقة غير مسموحة داخل ZIP');
    }
    final parts = path.split('/');
    final meaningful = parts.where((part) => part.isNotEmpty).toList();
    if (meaningful.isEmpty || meaningful.any((part) => part == '.' || part == '..')) {
      throw FormatException('مسار غير آمن داخل ZIP');
    }
    return meaningful.join('/');
  }

  static void validateArchive({
    required int entryCount,
    required Iterable<MapEntry<String, int>> files,
  }) {
    if (entryCount == 0) throw FormatException('ملف ZIP فارغ');
    if (entryCount > maxEntries) {
      throw FormatException('الأرشيف يحتوي على عدد كبير جدًا من العناصر');
    }
    var total = 0;
    for (final file in files) {
      normalizePath(file.key);
      final size = file.value;
      if (size < 0 || size > maxSingleFileBytes) {
        throw FormatException('حجم ملف غير مسموح: ${file.key}');
      }
      total += size;
      if (total > maxTotalBytes) {
        throw FormatException('الحجم الإجمالي للأرشيف يتجاوز الحد المسموح');
      }
    }
  }
  /// Rejects duplicate paths and file/directory collisions across ZIP entries.
  /// Implicit parent directories are accepted, but their casing must agree
  /// with any explicit directory entries and with every other file path.
  static void validateFilePaths(
    Iterable<String> filePaths, {
    Iterable<String> directoryPaths = const [],
  }) {
    final portableFiles = <String, String>{};
    final portableDirectories = <String, String>{};
    final normalizedFiles = <String>[];
    final normalizedDirectories = <String>[];

    for (final rawPath in filePaths) {
      final path = normalizePath(rawPath);
      final key = path.toLowerCase();
      final previous = portableFiles[key];
      if (previous != null) {
        if (previous == path) {
          throw FormatException('مسار مكرر داخل ZIP: $path');
        }
        throw FormatException(
          'مساران يتعارضان عند التشغيل على أنظمة الملفات غير الحساسة لحالة الأحرف: '
          '$previous و $path',
        );
      }
      portableFiles[key] = path;
      normalizedFiles.add(path);
    }

    for (final rawPath in directoryPaths) {
      final path = normalizePath(rawPath);
      final key = path.toLowerCase();
      final previous = portableDirectories[key];
      if (previous != null) {
        if (previous == path) {
          throw FormatException('مجلد مكرر داخل ZIP: $path');
        }
        throw FormatException(
          'مجلدان يتعارضان بسبب اختلاف حالة الأحرف داخل ZIP: '
          '$previous و $path',
        );
      }
      if (portableFiles.containsKey(key)) {
        throw FormatException('تعارض بين ملف ومجلد داخل ZIP: $path');
      }
      portableDirectories[key] = path;
      normalizedDirectories.add(path);
    }

    // Every implicit and explicit directory spelling must agree.
    final directorySpellings = <String, String>{};

    void registerDirectory(String directory) {
      final key = directory.toLowerCase();
      final previous = directorySpellings[key];

      if (previous != null && previous != directory) {
        throw FormatException(
          'مجلدان يختلفان في حالة الأحرف داخل ZIP: $previous و $directory',
        );
      }

      directorySpellings[key] = directory;

      if (portableFiles.containsKey(key)) {
        throw FormatException('تعارض ملف ومجلد داخل ZIP: $directory');
      }
    }

    // Files imply all their parent directories.
    for (final path in normalizedFiles) {
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        registerDirectory(parts.take(i).join('/'));
      }
    }

    // Explicit directory entries also imply their parents, and their own
    // complete path must be checked (including its casing).
    for (final path in normalizedDirectories) {
      final parts = path.split('/');
      for (var i = 1; i <= parts.length; i++) {
        registerDirectory(parts.take(i).join('/'));
      }
    }
  }


}

/// Tracks ZIP export resource limits while the SAF tree is being read.
/// Limits are enforced incrementally, before the full archive is assembled.
class ProjectArchiveBudget {
  int entryCount = 0;
  int totalBytes = 0;
  final Set<String> _registeredPaths = <String>{};
  final Map<String, String> _portablePaths = <String, String>{};

  void registerEntry(String rawPath, {required int byteCount}) {
    final path = ProjectArchiveValidator.normalizePath(rawPath);
    final portablePath = path.toLowerCase();
    final previous = _portablePaths[portablePath];
    if (previous != null) {
      if (previous == path) {
        throw FormatException('مسار مكرر أثناء تصدير المشروع: $path');
      }
      throw FormatException(
        'مساران يتعارضان عند التصدير لأنظمة الملفات غير الحساسة لحالة الأحرف: '
        '$previous و $path',
      );
    }
    if (!_registeredPaths.add(path)) {
      throw FormatException('مسار مكرر أثناء تصدير المشروع: $path');
    }
    _portablePaths[portablePath] = path;
    entryCount++;
    if (entryCount > ProjectArchiveValidator.maxEntries) {
      throw FormatException('المشروع يحتوي على عناصر أكثر من الحد المسموح للتصدير.');
    }
    if (byteCount < 0 || byteCount > ProjectArchiveValidator.maxSingleFileBytes) {
      throw FormatException('حجم الملف يتجاوز الحد المسموح للتصدير: $path');
    }
    totalBytes += byteCount;
    if (totalBytes > ProjectArchiveValidator.maxTotalBytes) {
      throw FormatException('الحجم الإجمالي للمشروع يتجاوز 256 ميجابايت.');
    }
  }
}
