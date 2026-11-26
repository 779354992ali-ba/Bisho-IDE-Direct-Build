import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/engine_health_report.dart';
import 'package:bisho_ide/core/services/local_build_environment.dart';

void main() {
  group('EngineHealthReport', () {
    test('does not report ready while runtime and build proofs are missing', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 35,
        'availableBytes': 16 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'alpineRootfsInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': false,
        'debugBuildVerified': false,
        'releaseBuildVerified': false,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
        'canBuildLocally': false,
      });

      final report = EngineHealthReport.fromEnvironment(environment);

      expect(report.failed, 0);
      expect(report.warnings, greaterThan(0));
      expect(report.isReady, isFalse);
    });

    test('reports ready only when all health checks pass', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 35,
        'availableBytes': 16 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'alpineRootfsInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'releaseBuildVerified': true,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
        'canBuildLocally': true,
      });

      final report = EngineHealthReport.fromEnvironment(environment);

      expect(report.failed, 0);
      expect(report.warnings, 0);
      expect(report.isReady, isTrue);
    });


    test('reports missing Alpine as a blocking failure', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'engineInstalled': true,
        'alpineRootfsInstalled': false,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'releaseBuildVerified': true,
        'availableBytes': 8 * 1024 * 1024 * 1024,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
      });

      final report = EngineHealthReport.fromEnvironment(environment);
      expect(report.checks.any((check) =>
          check.title == 'نظام Alpine ARM64' &&
          check.state == EngineCheckState.failed), isTrue);
      expect(report.isReady, isFalse);
    });

    test('reports known insufficient storage as a blocking failure', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'engineInstalled': true,
        'alpineRootfsInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'releaseBuildVerified': true,
        'availableBytes': 1,
        'requiredStorageBytes': 2,
      });

      final report = EngineHealthReport.fromEnvironment(environment);
      expect(report.checks.any((check) =>
          check.title == 'مساحة التخزين' &&
          check.state == EngineCheckState.failed), isTrue);
      expect(report.isReady, isFalse);
    });

    test('fails health report for a non-ARM64 device', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'armeabi-v7a',
        'engineInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'releaseBuildVerified': true,
        'availableBytes': 8 * 1024 * 1024 * 1024,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
      });

      final report = EngineHealthReport.fromEnvironment(environment);

      expect(report.failed, greaterThan(0));
      expect(report.isReady, isFalse);
    });
  });
}
