/// Central policy for excluding local caches and credentials from GitHub uploads.
class GitHubUploadPolicy {
  GitHubUploadPolicy._();

  static const excludedDirectories = <String>{
    '.git',
    'build',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.ssh',
    '.aws',
    '.azure',
  };

  static const excludedFiles = <String>{
    'local.properties',
    'key.properties',
    '.env',
    '.netrc',
    '.npmrc',
    '.pypirc',
    'credentials',
    'credentials.json',
    'secrets.json',
  };

  static const sensitiveExtensions = <String>{
    '.jks',
    '.keystore',
    '.pem',
    '.p12',
    '.pfx',
    '.key',
    '.p8',
    '.mobileprovision',
  };

  /// Detects GitHub's empty-repository response so the uploader can create
  /// an initial commit before publishing the complete project tree.
  static bool isEmptyRepositoryError(int statusCode, String message) {
    if (statusCode != 404 && statusCode != 409 && statusCode != 422) {
      return false;
    }
    final normalized = message.toLowerCase();
    return normalized.contains('repository is empty') ||
        normalized.contains('git repository is empty') ||
        normalized.contains('git database is empty');
  }

  /// Resolves the workflow file to dispatch. Prefer the explicitly requested
  /// path; when it is absent, fall back only if the project has one unambiguous
  /// workflow file. Multiple candidates must be selected by the user.
  static String resolveWorkflowPath(
    String requestedPath,
    Iterable<String> availablePaths,
  ) {
    final paths = availablePaths.toSet();
    if (paths.contains(requestedPath)) return requestedPath;
    final candidates = paths.where((path) {
      final normalized = path.toLowerCase();
      return normalized.startsWith('.github/workflows/') &&
          (normalized.endsWith('.yml') || normalized.endsWith('.yaml'));
    }).toList()..sort();
    return candidates.length == 1 ? candidates.single : requestedPath;
  }

  static bool shouldExcludeDirectory(String name) =>
      excludedDirectories.contains(name.toLowerCase());

  static bool shouldExcludeFile(String name) {
    final lower = name.toLowerCase();
    if (excludedFiles.contains(lower)) return true;
    // Keep safe templates while excluding environment-specific secrets.
    if (lower.startsWith('.env.') &&
        lower != '.env.example' && lower != '.env.sample') {
      return true;
    }
    return sensitiveExtensions.any((extension) => lower.endsWith(extension));
  }
}
