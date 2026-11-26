import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bisho_ide/core/services/github_repository_service.dart';

void main() {
  group('GitHubRepositoryService', () {
    test('returns the authenticated account without exposing the token', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/user');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(jsonEncode({
          'login': 'bisho-developer',
          'avatar_url': 'https://avatars.githubusercontent.com/u/1',
        }), 200);
      });
      final service = GitHubRepositoryService(client: client);
      final account = await service.verifyToken('test-token');
      expect(account.login, 'bisho-developer');
      expect(account.avatarUrl, contains('githubusercontent.com'));
      client.close();
    });


    test('dispatches the requested workflow on the selected branch', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/repos/demo/app/actions/workflows/build-android.yml/dispatches');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['ref'], 'main');
        expect((body['inputs'] as Map)['flutter_version'], '3.47.9');
        return http.Response('', 204);
      });
      final service = GitHubRepositoryService(client: client);
      await service.dispatchBuild(
        token: 'test-token',
        owner: 'demo',
        repository: 'app',
        workflow: 'build-android.yml',
        branch: 'main',
        flutterVersion: '3.47.9',
      );
      client.close();
    });

    test('reports a missing diagnostics artifact for a workflow run', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/repos/demo/app/actions/runs/123/artifacts');
        return http.Response(jsonEncode({'artifacts': []}), 200);
      });
      final service = GitHubRepositoryService(client: client);
      await expectLater(
        service.downloadBuildDiagnostics(
          token: 'test-token', owner: 'demo', repository: 'app', runId: 123,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message, 'message', contains('لا يوجد تقرير تشخيص صالح'),
        )),
      );
      client.close();
    });

    test('rejects an invalid token with a safe Arabic message', () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'message': 'Bad credentials'}), 401));
      final service = GitHubRepositoryService(client: client);
      await expectLater(
        service.verifyToken('invalid-token'),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('رمز GitHub غير صالح'),
        )),
      );
      client.close();
    });
    test('rejects empty or whitespace-containing tokens before network access', () async {
      final client = MockClient((request) async {
        fail('Invalid tokens must be rejected before sending a request.');
      });
      final service = GitHubRepositoryService(client: client);
      await expectLater(service.verifyToken('  '), throwsArgumentError);
      await expectLater(service.verifyToken('token with spaces'), throwsArgumentError);
      client.close();
    });

    test('rejects unsafe repository, owner, workflow and branch inputs', () async {
      final client = MockClient((request) async {
        fail('Unsafe path components must be rejected before network access.');
      });
      final service = GitHubRepositoryService(client: client);
      Future<void> dispatch({
        String owner = 'demo',
        String repository = 'app',
        String workflow = 'build-android.yml',
        String branch = 'main',
      }) => service.dispatchBuild(
        token: 'test-token',
        owner: owner,
        repository: repository,
        workflow: workflow,
        branch: branch,
        flutterVersion: '3.47.9',
      );

      await expectLater(dispatch(owner: '../attacker'), throwsArgumentError);
      await expectLater(dispatch(repository: '../repo'), throwsArgumentError);
      await expectLater(dispatch(workflow: '../outside.yml'), throwsArgumentError);
      await expectLater(dispatch(branch: 'main\\nmalicious'), throwsArgumentError);
      client.close();
    });

    test('does not echo arbitrary GitHub error response text', () async {
      const reflectedSecret = 'reflected-sensitive-server-detail';
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'message': reflectedSecret}), 500));
      final service = GitHubRepositoryService(client: client);
      await expectLater(
        service.verifyToken('test-token'),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('HTTP 500'), isNot(contains(reflectedSecret))),
        )),
      );
      client.close();
    });

    test('rejects non-positive workflow run identifiers before network access', () async {
      final client = MockClient((request) async {
        fail('Invalid run IDs must be rejected before network access.');
      });
      final service = GitHubRepositoryService(client: client);
      await expectLater(
        service.downloadBuildDiagnostics(
          token: 'test-token', owner: 'demo', repository: 'app', runId: 0,
        ),
        throwsArgumentError,
      );
      client.close();
    });

  });
}
