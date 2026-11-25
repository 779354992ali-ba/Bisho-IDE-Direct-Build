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

    test('handles absent or malformed job payloads safely', () {
      final result = GitHubWorkflowProgress.fromApiPayload({'jobs': null});

      expect(result.totalJobs, 0);
      expect(result.progress, 0);
      expect(result.jobLines, isEmpty);
    });
  });
}
