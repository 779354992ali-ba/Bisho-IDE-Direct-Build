/// A lightweight snapshot of GitHub Actions jobs for the Build Center.
class GitHubWorkflowProgress {
  const GitHubWorkflowProgress({
    required this.completedJobs,
    required this.totalJobs,
    required this.progress,
    required this.jobLines,
  });

  final int completedJobs;
  final int totalJobs;
  final double progress;
  final List<String> jobLines;

  factory GitHubWorkflowProgress.fromApiPayload(Object? payload) {
    if (payload is! Map) {
      return const GitHubWorkflowProgress(
        completedJobs: 0, totalJobs: 0, progress: 0, jobLines: [],
      );
    }
    final rawJobs = payload['jobs'];
    if (rawJobs is! List) {
      return const GitHubWorkflowProgress(
        completedJobs: 0, totalJobs: 0, progress: 0, jobLines: [],
      );
    }

    final jobs = rawJobs.whereType<Map>().toList(growable: false);
    if (jobs.isEmpty) {
      return const GitHubWorkflowProgress(
        completedJobs: 0, totalJobs: 0, progress: 0, jobLines: [],
      );
    }

    var completed = 0;
    var weightedProgress = 0.0;
    final lines = <String>[];
    for (final job in jobs) {
      final name = job['name']?.toString() ?? 'Job';
      final status = job['status']?.toString() ?? 'queued';
      final conclusion = job['conclusion']?.toString();
      if (status == 'completed') {
        completed++;
        weightedProgress += 1;
        lines.add('$name — ${conclusion ?? 'completed'}');
        continue;
      }

      final steps = (job['steps'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      if (status == 'in_progress' && steps.isNotEmpty) {
        final finishedSteps = steps.where(
          (step) => step['status']?.toString() == 'completed',
        ).length;
        weightedProgress += finishedSteps / steps.length;
        final active = steps.where(
          (step) => step['status']?.toString() == 'in_progress',
        );
        final activeName = active.isEmpty
            ? 'قيد التنفيذ'
            : active.first['name']?.toString() ?? 'قيد التنفيذ';
        lines.add('$name — $activeName');
      } else {
        lines.add('$name — $status');
      }
    }

    return GitHubWorkflowProgress(
      completedJobs: completed,
      totalJobs: jobs.length,
      progress: (weightedProgress / jobs.length).clamp(0.0, 1.0),
      jobLines: List.unmodifiable(lines),
    );
  }
}
