import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'saf_file_service.dart';

class LocalBuildProgress {
  const LocalBuildProgress(this.message, {this.isError = false});
  final String message;
  final bool isError;
}

/// Stages a SAF project into app-private storage and delegates execution to
/// the Android-side embedded Linux runtime. No shell command is run by Dart.
class LocalBuildRunner {
  static const _channel = 'com.bisho.ide/local_build';
  static const _events = 'com.bisho.ide/local_build/events';
  LocalBuildRunner();

  Stream<LocalBuildProgress> get progress =>
      const EventChannel(_events).receiveBroadcastStream().map((event) {
        final map = Map<Object?, Object?>.from(event as Map);
        return LocalBuildProgress(map['message']?.toString() ?? '',
            isError: map['isError'] == true);
      });

  Future<String> stageProject(String projectUri, String projectName) async {
    final result = await const MethodChannel(_channel)
        .invokeMapMethod<Object?, Object?>(
      'stageProjectFromSaf',
      {'projectUri': projectUri, 'projectName': projectName},
    );
    if (result?['success'] != true) {
      throw StateError(
        result?['message']?.toString() ?? 'تعذر تجهيز ملفات المشروع للبناء المحلي.',
      );
    }
    final path = result?['projectDirectory']?.toString() ?? '';
    if (path.isEmpty || !await Directory(path).exists()) {
      throw StateError('لم يتم إنشاء مجلد المشروع المرحلي بصورة صحيحة.');
    }
    if (!await File('$path/pubspec.yaml').exists()) {
      await removeStagedProject(path);
      throw StateError('المجلد المحدد ليس جذر مشروع Flutter صالحًا.');
    }
    return path;
  }

  Future<void> removeStagedProject(String projectDirectory) async {
    final directory = Directory(projectDirectory);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<String> build(String projectDirectory, {String mode = 'debug'}) async {
    if (mode != 'debug' && mode != 'release') {
      throw ArgumentError.value(mode, 'mode', 'وضع البناء يجب أن يكون debug أو release.');
    }
    final result = await const MethodChannel(_channel).invokeMapMethod<Object?, Object?>(
      'runBuild', {'projectDirectory': projectDirectory, 'mode': mode},
    );
    if (result == null || result['success'] != true) {
      throw StateError(result?['message']?.toString() ?? 'فشل تنفيذ البناء المحلي.');
    }
    final artifact = result['artifactPath']?.toString() ?? '';
    if (artifact.isEmpty || !artifact.toLowerCase().endsWith('.apk')) {
      throw StateError('انتهى أمر البناء دون إرجاع مسار APK صالح.');
    }
    final artifactFile = File(artifact);
    if (!await artifactFile.exists() || await artifactFile.length() < 64 * 1024) {
      throw StateError('انتهى أمر البناء دون العثور على APK مكتمل بالحجم المتوقع.');
    }
    return artifact;
  }

  Future<void> saveArtifactToSaf({
    required String artifactPath,
    required String parentUri,
    String fileName = 'app-release.apk',
  }) async {
    final result = await const MethodChannel(_channel).invokeMapMethod<Object?, Object?>(
      'saveArtifactToSaf', {
        'artifactPath': artifactPath,
        'parentUri': parentUri,
        'fileName': SafFileService.validateChildName(fileName),
      },
    );
    if (result?['success'] != true) {
      throw StateError(result?['message']?.toString() ?? 'تعذر حفظ APK في مجلد المشروع.');
    }
  }

  Future<void> cancel() => const MethodChannel(_channel).invokeMethod<void>('cancelBuild');
}
