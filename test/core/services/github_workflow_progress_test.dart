import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/github_workflow_progress.dart';

void main() {
  group('GitHubWorkflowProgress', () {
    test('returns zero progress when jobs are queued', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [
          {'name': 'analyze', 'status': 'queued'},
          {'name': 'test', 'status': 'queued'},
        ],
      });

      expect(result.completedJobs, 0);
      expect(result.totalJobs, 2);
      expect(result.progress, 0);
      expect(result.jobLines, hasLength(2));
    });

    test('counts completed jobs and completed steps in the active job', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [
          {'name': 'analyze', 'status': 'completed', 'conclusion': 'success'},
          {
            'name': 'tests',
            'status': 'in_progress',
            'steps': [
              {'name': 'checkout', 'status': 'completed'},
              {'name': 'flutter test', 'status': 'in_progress'},
              {'name': 'upload', 'status': 'pending'},
            ],
          },
          {'name': 'release', 'status': 'queued'},
        ],
      });

      expect(result.completedJobs, 1);
      expect(result.totalJobs, 3);
      expect(result.progress, closeTo(4 / 9, 0.0001));
      expect(result.jobLines[1], contains('flutter test'));
    });

    test('treats completed failed jobs as finished work', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [
          {'name': 'analyze', 'status': 'completed', 'conclusion': 'failure'},
        ],
      });

      expect(result.completedJobs, 1);
      expect(result.progress, 1);
      expect(result.jobLines.single, contains('failure'));
    });


    test('summarizes failed, skipped, active and waiting jobs separately', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [
          {'name': 'analyze', 'status': 'completed', 'conclusion': 'failure'},
          {'name': 'optional', 'status': 'completed', 'conclusion': 'skipped'},
          {'name': 'tests', 'status': 'in_progress', 'steps': [
            {'name': 'setup', 'status': 'skipped'},
            {'name': 'test', 'status': 'in_progress'},
          ]},
          {'name': 'release', 'status': 'waiting'},
        ],
      });

      expect(result.completedJobs, 2);
      expect(result.failedJobs, 1);
      expect(result.skippedJobs, 1);
      expect(result.activeJobs, 1);
      expect(result.queuedJobs, 1);
      expect(result.progress, closeTo(5 / 8, 0.0001));
    });

    test('does not count malformed job entries as jobs', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [null, 'invalid', 7, {'name': 'build', 'status': 'queued'}],
      });

      expect(result.totalJobs, 1);
      expect(result.queuedJobs, 1);
      expect(result.progress, 0);
    });

    test('keeps progress bounded for unexpected step payloads', () {
      final result = GitHubWorkflowProgress.fromApiPayload({
        'jobs': [
          {'name': 'build', 'status': 'in_progress', 'steps': 'not-a-list'},
        ],
      });

      expect(result.progress, 0);
      expect(result.activeJobs, 1);
    });

    test('handles absent or malformed job payloads safely', () {
      final result = GitHubWorkflowProgress.fromApiPayload({'jobs': null});

      expect(result.totalJobs, 0);
      expect(result.progress, 0);
      expect(result.jobLines, isEmpty);
    });
  });
}
