import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bisho_ide/core/services/flutter_package_catalog_service.dart';

void main() {
  group('FlutterPackageCatalogService', () {
    test('searches pub.dev and returns unique package names', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'pub.dev');
        expect(request.url.path, '/api/search');
        expect(request.url.queryParameters['q'], 'http');
        return http.Response(jsonEncode({
          'packages': [
            {'package': 'http'},
            {'package': 'provider'},
            {'package': 'http'},
          ],
        }), 200);
      });
      final service = FlutterPackageCatalogService(client: client);
      expect(await service.searchPackages('http'), ['http', 'provider']);
      service.close();
    });

    test('reads latest stable package details', () async {
      final client = MockClient((request) async => http.Response(jsonEncode({
        'latest': {
          'version': '2.3.4',
          'pubspec': {'description': 'A useful package'},
        },
      }), 200));
      final service = FlutterPackageCatalogService(client: client);
      final info = await service.packageInfo('demo_package');
      expect(info.latestVersion, '2.3.4');
      expect(info.description, 'A useful package');
      service.close();
    });

    test('parses only direct dependencies in the selected section', () {
      const source = '''
name: demo
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
dev_dependencies:
  flutter_test:
    sdk: flutter
''';
      expect(
        FlutterPackageCatalogService.readDependencies(source),
        {'flutter': '', 'http': '^1.2.0'},
      );
      expect(
        FlutterPackageCatalogService.readDependencies(source, section: 'dev_dependencies'),
        {'flutter_test': ''},
      );
    });

    test('adds or updates a dependency without touching other sections', () {
      const source = 'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n\ndev_dependencies:\n  test: ^1.0.0\n';
      final added = FlutterPackageCatalogService.addDependency(
        source,
        name: 'http',
        version: '1.2.3',
      );
      expect(added, contains('  http: ^1.2.3'));
      expect(added, contains('  test: ^1.0.0'));
      final updated = FlutterPackageCatalogService.addDependency(
        added,
        name: 'http',
        version: '2.0.0',
      );
      expect('http:'.allMatches(updated).length, 1);
      expect(updated, contains('  http: ^2.0.0'));
    });

    test('removes only the requested direct dependency', () {
      const source = 'dependencies:\n  flutter:\n    sdk: flutter\n  http: ^1.0.0\n  path: ^1.0.0\n';
      final result = FlutterPackageCatalogService.removeDependency(source, name: 'http');
      expect(result, isNot(contains('http:')));
      expect(result, contains('flutter:'));
      expect(result, contains('path:'));
    });

    test('rejects invalid package names and versions', () {
      expect(
        () => FlutterPackageCatalogService.addDependency(
          'dependencies:\n', name: '../bad', version: '1.0.0',
        ),
        throwsArgumentError,
      );
      expect(
        () => FlutterPackageCatalogService.addDependency(
          'dependencies:\n', name: 'good', version: 'latest',
        ),
        throwsArgumentError,
      );
    });
  });
}
