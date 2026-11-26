import 'package:flutter/services.dart';

/// Device and toolchain diagnostics for the on-device build feature.
///
/// A local build is reported as available only after the native layer confirms
/// an executable, compatible toolchain. A manifest or downloaded files alone
/// are never sufficient proof.
class LocalBuildEnvironment {
  const LocalBuildEnvironment({
    required this.deviceAbi,
    required this.androidVersion,
    required this.availableBytes,
    required this.engineInstalled,
    required this.alpineRootfsInstalled,
    required this.deviceSupported,
    required this.runtimeVerified,
    required this.debugBuildVerified,
    required this.releaseBuildVerified,
    required this.requiredStorageBytes,
    required this.missingRequirements,
    required this.canBuildLocally,
    required this.message,
  });

  final String deviceAbi;
  final int androidVersion;
  final int availableBytes;
  final bool engineInstalled;
  final bool alpineRootfsInstalled;
  final bool deviceSupported;
  final bool runtimeVerified;
  final bool debugBuildVerified;
  final bool releaseBuildVerified;
  final int requiredStorageBytes;
  final List<String> missingRequirements;
  final bool canBuildLocally;
  final String message;

  static int _readInt(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  factory LocalBuildEnvironment.fromMap(Map<Object?, Object?> map) {
    final engineInstalled = map['engineInstalled'] == true;
    final deviceSupported = map['deviceSupported'] == true;
    final runtimeVerified = map['runtimeVerified'] == true;
    final debugBuildVerified = map['debugBuildVerified'] == true;
    final releaseBuildVerified = map['releaseBuildVerified'] == true;
    return LocalBuildEnvironment(
      deviceAbi: map['deviceAbi']?.toString() ?? 'غير معروف',
      androidVersion: _readInt(map['androidVersion']),
      availableBytes: _readInt(map['availableBytes']),
      engineInstalled: engineInstalled,
      alpineRootfsInstalled: map['alpineRootfsInstalled'] == true,
      deviceSupported: deviceSupported,
      runtimeVerified: runtimeVerified,
      debugBuildVerified: debugBuildVerified,
      releaseBuildVerified: releaseBuildVerified,
      requiredStorageBytes: _readInt(map['requiredStorageBytes']),
      missingRequirements: (map['missingRequirements'] is List
              ? map['missingRequirements'] as List
              : const <Object?>[])
          .map((item) => item.toString())
          .toList(growable: false),
      // This flag is deliberately fail-closed. A manifest is not an
      // end-to-end build test and cannot enable the build button.
      canBuildLocally: map['canBuildLocally'] == true &&
          engineInstalled &&
          alpineRootfsInstalled &&
          deviceSupported &&
          runtimeVerified &&
          debugBuildVerified,
      message: map['message']?.toString() ?? 'تعذر تحديد حالة بيئة البناء.',
    );
  }

  String get availableStorageLabel => _formatBytes(availableBytes);

  String get requiredStorageLabel => _formatBytes(requiredStorageBytes);

  bool get hasKnownStorage => availableBytes > 0 && requiredStorageBytes > 0;

  bool get hasSufficientStorage =>
      hasKnownStorage && availableBytes >= requiredStorageBytes;

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return 'غير متاح';
    final gib = bytes / (1024 * 1024 * 1024);
    return '${gib.toStringAsFixed(1)} GB';
  }
}

class LocalBuildEnvironmentService {
  static const MethodChannel _channel =
      MethodChannel('com.bisho.ide/local_build');

  Future<LocalBuildEnvironment> inspect() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'inspectEnvironment',
      );
      if (result == null) {
        throw PlatformException(
          code: 'EMPTY_RESULT',
          message: 'لم تُرجع خدمة Android معلومات بيئة البناء.',
        );
      }
      return LocalBuildEnvironment.fromMap(result);
    } on PlatformException catch (error) {
      return _unavailable(
        'فشل فحص محرك البناء المحلي: ${error.message ?? error.code}',
      );
    } on MissingPluginException {
      return _unavailable(
        'خدمة البناء المحلية غير مدمجة في هذه النسخة من التطبيق.',
      );
    }
  }

  Future<Map<Object?, Object?>> probeEngine() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('probeEngine');
      return result ??
          <Object?, Object?>{
            'success': false,
            'message': 'لم تُرجع خدمة المحرك نتيجة الاختبار.',
          };
    } on PlatformException catch (error) {
      return <Object?, Object?>{
        'success': false,
        'message': error.message ?? error.code,
      };
    } on MissingPluginException {
      return <Object?, Object?>{
        'success': false,
        'message': 'خدمة فحص المحرك غير مدمجة في هذه النسخة.',
      };
    } catch (error) {
      return <Object?, Object?>{
        'success': false,
        'message': 'تعذر فحص المحرك: $error',
      };
    }
  }

  LocalBuildEnvironment _unavailable(String message) {
    return LocalBuildEnvironment(
      deviceAbi: 'غير معروف',
      androidVersion: 0,
      availableBytes: 0,
      engineInstalled: false,
      alpineRootfsInstalled: false,
      deviceSupported: false,
      runtimeVerified: false,
      debugBuildVerified: false,
      releaseBuildVerified: false,
      requiredStorageBytes: 1024 * 1024 * 1024,
      missingRequirements: const [],
      canBuildLocally: false,
      message: message,
    );
  }
}
