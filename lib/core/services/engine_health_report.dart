import 'local_build_environment.dart';

enum EngineCheckState { passed, warning, failed }

class EngineHealthCheck {
  const EngineHealthCheck({
    required this.title,
    required this.detail,
    required this.state,
  });

  final String title;
  final String detail;
  final EngineCheckState state;
}

/// Read-only health summary. It never repairs, deletes, moves, or replaces
/// engine files; all results come from the native environment inspection.
class EngineHealthReport {
  const EngineHealthReport({
    required this.checks,
    required this.passed,
    required this.warnings,
    required this.failed,
  });

  final List<EngineHealthCheck> checks;
  final int passed;
  final int warnings;
  final int failed;

  bool get isReady => failed == 0 && warnings == 0;

  String get headline {
    if (failed > 0) return 'يوجد ${failed} خللًا يحتاج إلى معالجة';
    if (warnings > 0) return 'المحرك موجود، لكن بعض الاختبارات لم تكتمل';
    return 'اجتازت جميع الفحوص المسجلة';
  }

  factory EngineHealthReport.fromEnvironment(LocalBuildEnvironment value) {
    final abi = value.deviceAbi.toLowerCase();
    final isArm64 = abi.contains('arm64') || abi.contains('aarch64');
    final checks = <EngineHealthCheck>[
      EngineHealthCheck(
        title: 'معمارية ARM64',
        detail: isArm64 ? 'المعمارية متوافقة: ${value.deviceAbi}' : 'المعمارية غير مؤكدة: ${value.deviceAbi}',
        state: isArm64 ? EngineCheckState.passed : EngineCheckState.failed,
      ),
      EngineHealthCheck(
        title: 'دعم الجهاز',
        detail: value.deviceSupported ? 'الجهاز يحقق متطلبات التشغيل الأولية' : 'الجهاز أو متطلبات التشغيل غير مكتملة',
        state: value.deviceSupported ? EngineCheckState.passed : EngineCheckState.failed,
      ),
      EngineHealthCheck(
        title: 'نظام Alpine ARM64',
        detail: value.alpineRootfsInstalled
            ? 'بيئة Alpine الموجودة تم تأكيدها من طبقة Android'
            : 'لم يتم تأكيد وجود Alpine؛ لن يُعلن عن جاهزية البناء المحلي',
        state: value.alpineRootfsInstalled
            ? EngineCheckState.passed
            : EngineCheckState.failed,
      ),
      EngineHealthCheck(
        title: 'ملفات المحرك',
        detail: value.engineInstalled ? 'تم العثور على ملفات المحرك' : 'لم يتم تأكيد وجود ملفات المحرك',
        state: value.engineInstalled ? EngineCheckState.passed : EngineCheckState.failed,
      ),
      EngineHealthCheck(
        title: 'اختبار runtime',
        detail: value.runtimeVerified ? 'تم التحقق من تشغيل بيئة المحرك' : 'لم يتم إثبات تشغيل بيئة المحرك بعد',
        state: value.runtimeVerified ? EngineCheckState.passed : EngineCheckState.warning,
      ),
      EngineHealthCheck(
        title: 'بناء Debug',
        detail: value.debugBuildVerified ? 'تم بناء APK والتحقق منه' : 'لم ينجح اختبار بناء Debug بعد',
        state: value.debugBuildVerified ? EngineCheckState.passed : EngineCheckState.warning,
      ),
      EngineHealthCheck(
        title: 'بناء Release/AOT',
        detail: value.releaseBuildVerified ? 'تم التحقق من بناء Release' : 'غير معتمد؛ نجاح Debug لا يثبت جاهزية Release',
        state: value.releaseBuildVerified ? EngineCheckState.passed : EngineCheckState.warning,
      ),
      EngineHealthCheck(
        title: 'مساحة التخزين',
        detail: 'المتاح ${value.availableStorageLabel} — المطلوب ${value.requiredStorageLabel}',
        state: !value.hasKnownStorage
            ? EngineCheckState.warning
            : value.hasSufficientStorage
                ? EngineCheckState.passed
                : EngineCheckState.failed,
      ),
    ];
    final passed = checks.where((item) => item.state == EngineCheckState.passed).length;
    final warnings = checks.where((item) => item.state == EngineCheckState.warning).length;
    final failed = checks.where((item) => item.state == EngineCheckState.failed).length;
    return EngineHealthReport(
      checks: List.unmodifiable(checks),
      passed: passed,
      warnings: warnings,
      failed: failed,
    );
  }
}
