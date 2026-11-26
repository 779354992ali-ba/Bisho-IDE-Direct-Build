/// A lightweight snapshot of GitHub Actions jobs for the Build Center.
class GitHubWorkflowProgress {
  const GitHubWorkflowProgress({
    required this.completedJobs,
    required this.totalJobs,
    required this.progress,
    required this.jobLines,
    this.failedJobs = 0,
    this.activeJobs = 0,
    this.queuedJobs = 0,
    this.skippedJobs = 0,
  });

  final int completedJobs;
  final int totalJobs;
  final double progress;
  final List<String> jobLines;
  final int failedJobs;
  final int activeJobs;
  final int queuedJobs;
  final int skippedJobs;

  factory GitHubWorkflowProgress.fromApiPayload(Object? payload) {
    if (payload is! Map) return _empty();
    final rawJobs = payload['jobs'];
    if (rawJobs is! List) return _empty();

    final jobs = rawJobs.whereType<Map>().toList(growable: false);
    if (jobs.isEmpty) return _empty();

    var completed = 0;
    var failed = 0;
    var activeJobs = 0;
    var queuedJobs = 0;
    var skippedJobs = 0;
    var weightedProgress = 0.0;
    final lines = <String>[];

    for (final job in jobs) {
      final name = job['name']?.toString().trim();
      final safeName = name == null || name.isEmpty ? 'Job' : name;
      final status = job['status']?.toString() ?? 'queued';
      final conclusion = job['conclusion']?.toString();

      if (status == 'completed') {
        completed++;
        weightedProgress += 1;
        if (conclusion == 'failure' || conclusion == 'timed_out' ||
            conclusion == 'action_required') {
          failed++;
        }
        if (conclusion == 'skipped') skippedJobs++;
        lines.add('$safeName — ${conclusion ?? 'completed'}');
        continue;
      }

      if (status == 'in_progress') {
        activeJobs++;
      } else if (status == 'queued' || status == 'waiting' ||
          status == 'pending' || status == 'requested') {
        queuedJobs++;
      }

      final steps = (job['steps'] is List ? job['steps'] as List : const [])
          .whereType<Map>()
          .toList(growable: false);
      if (status == 'in_progress' && steps.isNotEmpty) {
        final finishedSteps = steps.where((step) {
          final stepStatus = step['status']?.toString();
          return stepStatus == 'completed' || stepStatus == 'skipped';
        }).length;
        weightedProgress += finishedSteps / steps.length;
        final active = steps.where(
          (step) => step['status']?.toString() == 'in_progress',
        );
        final activeName = active.isEmpty
            ? 'قيد التنفيذ'
            : active.first['name']?.toString() ?? 'قيد التنفيذ';
        lines.add('$safeName — $activeName');
      } else {
        lines.add('$safeName — $status');
      }
    }

    return GitHubWorkflowProgress(
      completedJobs: completed,
      totalJobs: jobs.length,
      progress: (weightedProgress / jobs.length).clamp(0.0, 1.0).toDouble(),
      jobLines: List.unmodifiable(lines),
      failedJobs: failed,
      activeJobs: activeJobs,
      queuedJobs: queuedJobs,
      skippedJobs: skippedJobs,
    );
  }

  static GitHubWorkflowProgress _empty() => const GitHubWorkflowProgress(
        completedJobs: 0,
        totalJobs: 0,
        progress: 0,
        jobLines: [],
      );
}
