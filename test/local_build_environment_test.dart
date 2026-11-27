import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/services/local_build_environment.dart';

void main() {
  group('LocalBuildEnvironment', () {
    test('does not report ready without an installed engine', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 30,
        'availableBytes': 1024 * 1024 * 1024,
        'engineInstalled': false,
        'deviceSupported': true,
        'runtimeVerified': true,
        'requiredStorageBytes': 12 * 1024 * 1024 * 1024,
        'canBuildLocally': true,
        'message': 'not ready',
      });

      expect(environment.canBuildLocally, isFalse);
      expect(environment.engineInstalled, isFalse);
      expect(environment.deviceAbi, 'arm64-v8a');
    });

    test('does not trust an engine marker without native verification', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 30,
        'availableBytes': 2 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': false,
        'requiredStorageBytes': 12 * 1024 * 1024 * 1024,
        'canBuildLocally': false,
        'message': 'toolchain not verified',
      });

      expect(environment.engineInstalled, isTrue);
      expect(environment.canBuildLocally, isFalse);
    });


    test('never enables local build without native runtime verification', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 35,
        'availableBytes': 20 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'deviceSupported': true,
        'requiredStorageBytes': 12 * 1024 * 1024 * 1024,
        'runtimeVerified': false,
        'canBuildLocally': true,
        'message': 'manifest only',
      });

      expect(environment.canBuildLocally, isFalse);
      expect(environment.runtimeVerified, isFalse);
      expect(environment.releaseBuildVerified, isFalse);
    });


    test('defaults Release/AOT proof to false when native field is absent', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 35,
        'availableBytes': 8 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'alpineRootfsInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'canBuildLocally': true,
      });

      expect(environment.debugBuildVerified, isTrue);
      expect(environment.releaseBuildVerified, isFalse);
      expect(environment.canBuildLocally, isTrue);
    });

    test('does not enable local builds without runtime verification', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 35,
        'availableBytes': 8 * 1024 * 1024 * 1024,
        'engineInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': false,
        'debugBuildVerified': true,
        'releaseBuildVerified': false,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
        'canBuildLocally': true,
        'message': 'debug verified only',
      });

      expect(environment.debugBuildVerified, isTrue);
      expect(environment.releaseBuildVerified, isFalse);
      expect(environment.canBuildLocally, isFalse);
    });

    test('exposes missing requirements from native diagnostics', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'armeabi-v7a',
        'androidVersion': 28,
        'availableBytes': 100,
        'engineInstalled': false,
        'deviceSupported': false,
        'runtimeVerified': false,
        'requiredStorageBytes': 12 * 1024 * 1024 * 1024,
        'missingRequirements': ['arm64-v8a required', 'Android 10 required'],
        'canBuildLocally': false,
        'message': 'unsupported',
      });

      expect(environment.missingRequirements, hasLength(2));
      expect(environment.requiredStorageLabel, '12.0 GB');
      expect(environment.deviceSupported, isFalse);
    });


    test('Alpine rootfs is not assumed installed when native status is absent', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 30,
        'availableBytes': 3 * 1024 * 1024 * 1024,
        'engineInstalled': false,
        'deviceSupported': true,
        'canBuildLocally': false,
      });
      expect(environment.alpineRootfsInstalled, isFalse);
    });

    test('recovers safely from malformed native diagnostic field types', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': '35',
        'availableBytes': '2147483648',
        'engineInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'requiredStorageBytes': false,
        'missingRequirements': 'not-a-list',
        'canBuildLocally': true,
      });

      expect(environment.androidVersion, 35);
      expect(environment.availableBytes, 2147483648);
      expect(environment.requiredStorageBytes, 0);
      expect(environment.missingRequirements, isEmpty);
      expect(environment.canBuildLocally, isFalse);
    });

    test('requires verified runtime and Alpine before enabling local builds', () {
      final missingRuntime = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'engineInstalled': true,
        'alpineRootfsInstalled': true,
        'deviceSupported': true,
        'runtimeVerified': false,
        'debugBuildVerified': true,
        'canBuildLocally': true,
      });
      final missingAlpine = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'engineInstalled': true,
        'alpineRootfsInstalled': false,
        'deviceSupported': true,
        'runtimeVerified': true,
        'debugBuildVerified': true,
        'canBuildLocally': true,
      });

      expect(missingRuntime.canBuildLocally, isFalse);
      expect(missingAlpine.canBuildLocally, isFalse);
    });

    test('exposes storage sufficiency without treating unknown values as sufficient', () {
      final enough = LocalBuildEnvironment.fromMap({
        'availableBytes': 4 * 1024 * 1024 * 1024,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
      });
      final insufficient = LocalBuildEnvironment.fromMap({
        'availableBytes': 1,
        'requiredStorageBytes': 2,
      });
      final unknown = LocalBuildEnvironment.fromMap({});

      expect(enough.hasSufficientStorage, isTrue);
      expect(insufficient.hasSufficientStorage, isFalse);
      expect(unknown.hasKnownStorage, isFalse);
      expect(unknown.hasSufficientStorage, isFalse);
    });

    test('parses detailed storage usage without trusting missing fields', () {
      final environment = LocalBuildEnvironment.fromMap({
        'availableBytes': 3 * 1024 * 1024 * 1024,
        'requiredStorageBytes': 2 * 1024 * 1024 * 1024,
        'storageBreakdown': [
          {'label': 'Alpine RootFS', 'bytes': 1024 * 1024 * 1024},
          {'label': 'Gradle', 'bytes': '524288000'},
          {'label': 'invalid', 'bytes': false},
        ],
      });

      expect(environment.storageBreakdown, hasLength(3));
      expect(environment.storageBreakdown[0].label, 'Alpine RootFS');
      expect(environment.storageBreakdown[0].sizeLabel, '1.00 GB');
      expect(environment.storageBreakdown[1].bytes, 524288000);
      expect(environment.storageBreakdown[2].bytes, 0);
    });

    test('formats available storage in GiB', () {
      final environment = LocalBuildEnvironment.fromMap({
        'deviceAbi': 'arm64-v8a',
        'androidVersion': 30,
        'availableBytes': 2 * 1024 * 1024 * 1024,
        'engineInstalled': false,
        'deviceSupported': false,
        'runtimeVerified': false,
        'requiredStorageBytes': 12 * 1024 * 1024 * 1024,
        'missingRequirements': ['insufficient storage'],
        'canBuildLocally': false,
        'message': 'missing',
      });

      expect(environment.availableStorageLabel, '2.0 GB');
    });
  });
}
