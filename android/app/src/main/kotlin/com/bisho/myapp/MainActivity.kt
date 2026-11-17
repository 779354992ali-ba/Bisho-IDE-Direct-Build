package com.bisho.myapp

import android.os.Build
import android.net.Uri
import android.provider.DocumentsContract
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors
import org.json.JSONObject
import java.io.File
import java.io.BufferedInputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val localBuildChannel = "com.bisho.ide/local_build"
    // Installing/updating a full engine needs room for the ZIP and extracted
    // rootfs. Once installed, normal builds need a smaller but still safe reserve.
    private val engineInstallStorageBytes = 20L * 1024L * 1024L * 1024L
    private val minimumBuildStorageBytes = 5L * 1024L * 1024L * 1024L
    private val buildExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var activeBuildProcess: Process? = null
    @Volatile private var stagingCancelled: Boolean = false
    @Volatile private var buildEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$localBuildChannel/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    buildEventSink = events
                }
                override fun onCancel(arguments: Any?) { buildEventSink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localBuildChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspectEnvironment" -> {
                        buildExecutor.execute {
                            val environment = try { inspectLocalBuildEnvironment() } catch (error: Exception) {
                                mapOf("deviceAbi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
                                    "androidVersion" to Build.VERSION.SDK_INT, "availableBytes" to StatFs(filesDir.absolutePath).availableBytes,
                                    "requiredStorageBytes" to engineInstallStorageBytes, "engineInstallStorageBytes" to engineInstallStorageBytes,
                                    "deviceSupported" to false, "engineInstalled" to false, "runtimeVerified" to false,
                                    "debugBuildVerified" to false, "canBuildLocally" to false,
                                    "missingRequirements" to listOf(error.message ?: "تعذر فحص بيئة البناء."),
                                    "message" to (error.message ?: "تعذر فحص بيئة البناء."))
                            }
                            runOnUiThread { result.success(environment) }
                        }
                    }
                    "probeEngine" -> {
                        buildExecutor.execute {
                            val probe = try {
                                probeLocalBuildEngine()
                            } catch (error: Exception) {
                                mapOf("success" to false, "message" to (error.message ?: "تعذر اختبار المحرك."))
                            }
                            runOnUiThread { result.success(probe) }
                        }
                    }
                    "installEngine" -> {
                        val archivePath = call.argument<String>("archivePath")
                        val sha256 = call.argument<String>("sha256")
                        buildExecutor.execute {
                            try {
                                if (archivePath.isNullOrBlank() || sha256.isNullOrBlank()) {
                                    throw IllegalArgumentException("بيانات حزمة المحرك غير مكتملة.")
                                }
                                val installed = installLocalBuildEngine(archivePath, sha256)
                                runOnUiThread { result.success(installed) }
                            } catch (error: Exception) {
                                runOnUiThread { result.success(mapOf("success" to false, "message" to (error.message ?: "فشل تثبيت المحرك."))) }
                            }
                        }
                    }
                    "stageProjectFromSaf" -> {
                        val projectUri = call.argument<String>("projectUri")
                        val projectName = call.argument<String>("projectName") ?: "project"
                        if (projectUri.isNullOrBlank()) {
                            result.error("INVALID_PROJECT_URI", "رابط مجلد المشروع غير صالح.", null)
                        } else {
                            buildExecutor.execute {
                                try {
                                    val staged = stageProjectFromSaf(projectUri, projectName)
                                    runOnUiThread { result.success(mapOf("success" to true, "projectDirectory" to staged.absolutePath)) }
                                } catch (error: Exception) {
                                    runOnUiThread { result.success(mapOf("success" to false, "message" to (error.message ?: "تعذر تجهيز المشروع للبناء."))) }
                                }
                            }
                        }
                    }
                    "runBuild" -> {
                        val project = call.argument<String>("projectDirectory")
                        val mode = call.argument<String>("mode") ?: "debug"
                        if (project.isNullOrBlank()) {
                            result.error("INVALID_PROJECT", "مسار المشروع غير صالح.", null)
                        } else if (mode != "debug" && mode != "release") {
                            result.error("INVALID_BUILD_MODE", "وضع البناء غير مدعوم.", null)
                        } else {
                            buildExecutor.execute { executeLocalBuild(project, mode, result) }
                        }
                    }
                    "saveArtifactToSaf" -> {
                        val artifactPath = call.argument<String>("artifactPath")
                        val parentUri = call.argument<String>("parentUri")
                        val fileName = call.argument<String>("fileName")
                        if (artifactPath.isNullOrBlank() || parentUri.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.success(mapOf("success" to false, "message" to "بيانات حفظ APK غير مكتملة."))
                        } else {
                            buildExecutor.execute {
                                try {
                                    val saved = saveArtifactToSaf(artifactPath, parentUri, fileName)
                                    runOnUiThread { result.success(mapOf("success" to true, "uri" to saved.first, "bytes" to saved.second)) }
                                } catch (error: Exception) {
                                    runOnUiThread { result.success(mapOf("success" to false, "message" to (error.message ?: "تعذر حفظ APK."))) }
                                }
                            }
                        }
                    }
                    "cancelBuild" -> {
                        stagingCancelled = true
                        val running = activeBuildProcess
                        if (running != null) {
                            if (Build.VERSION.SDK_INT >= 26) running.destroyForcibly() else running.destroy()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }


    /** Verify the downloaded archive and extract it without loading it into RAM. */
    private fun installLocalBuildEngine(archivePath: String, expectedSha256: String): Map<String, Any> {
        if (!expectedSha256.matches(Regex("^[a-fA-F0-9]{64}$"))) {
            throw IllegalArgumentException("بصمة SHA-256 غير صالحة.")
        }
        val downloads = File(filesDir, "bisho-engine-downloads").canonicalFile
        val archive = File(archivePath).canonicalFile
        if (!archive.path.startsWith(downloads.path + File.separator) || !archive.isFile || archive.length() <= 0L) {
            throw IllegalArgumentException("ملف الحزمة خارج مجلد التنزيل الآمن أو غير موجود.")
        }
        if (archive.length() > 8L * 1024L * 1024L * 1024L) {
            throw IllegalArgumentException("حجم الحزمة يتجاوز 8 GB.")
        }
        val freeBytes = StatFs(filesDir.absolutePath).availableBytes
        // The downloaded ZIP already occupies part of the 20 GB install budget.
        // Reserve the remaining extraction budget instead of requiring another
        // full 20 GB after the archive has been downloaded.
        val remainingBudget = (engineInstallStorageBytes - archive.length()).coerceAtLeast(0L)
        if (freeBytes < remainingBudget) {
            throw IllegalStateException("المساحة الحرة لا تكفي لفك المحرك بأمان؛ يلزم ${remainingBudget / (1024L * 1024L * 1024L)} GB إضافية على الأقل.")
        }
        emitBuildEvent("جارٍ حساب SHA-256 لحزمة المحرك...")
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(archive).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actual.equals(expectedSha256, ignoreCase = true)) {
            throw SecurityException("فشلت مطابقة SHA-256؛ لم يتم تثبيت أي ملف.")
        }

        val engineRoot = File(filesDir, "bisho-local-build-engine")
        val staging = File(filesDir, "bisho-local-build-engine.installing")
        val backup = File(filesDir, "bisho-local-build-engine.previous")
        if (staging.exists()) staging.deleteRecursively()
        if (!staging.mkdirs()) throw IllegalStateException("تعذر إنشاء مجلد التثبيت المؤقت.")
        var extractedBytes = 0L
        var entries = 0
        val extractedNames = HashSet<String>()
        val canonicalTargets = HashSet<String>()
        try {
            ZipInputStream(BufferedInputStream(FileInputStream(archive), 1024 * 1024)).use { zip ->
                val buffer = ByteArray(256 * 1024)
                while (true) {
                    val entry = zip.nextEntry ?: break
                    entries++
                    if (entries > 100000) throw IllegalStateException("تحتوي الحزمة على عدد ملفات يتجاوز الحد الآمن.")
                    val rawName = entry.name.replace('\\', '/')
                    val name = if (entry.isDirectory) rawName.removeSuffix("/") else rawName
                    if (name.isBlank() || name.startsWith("/") || name.contains('\u0000') ||
                        name.split('/').any { it.isBlank() || it == ".." || it == "." } ||
                        Regex("^[A-Za-z]:").containsMatchIn(name)) {
                        throw SecurityException("تحتوي الحزمة على مسار ملف غير آمن أو غير قياسي.")
                    }
                    if (!extractedNames.add(name)) {
                        throw SecurityException("تحتوي الحزمة على مدخل ZIP مكرر: $name")
                    }
                    val output = File(staging, name).canonicalFile
                    if (!output.path.startsWith(staging.canonicalPath + File.separator)) {
                        throw SecurityException("تم رفض مسار استخراج خارج مجلد المحرك.")
                    }
                    // Different ZIP spellings (for example a//b and a/b) can
                    // normalize to the same destination on the filesystem.
                    if (!canonicalTargets.add(output.path)) {
                        throw SecurityException("تحتوي الحزمة على مسارات مختلفة تشير إلى الملف نفسه: $name")
                    }
                    if (entry.isDirectory) {
                        if (!output.exists() && !output.mkdirs()) throw IllegalStateException("تعذر إنشاء مجلد من الحزمة.")
                    } else {
                        output.parentFile?.let { if (!it.exists() && !it.mkdirs()) throw IllegalStateException("تعذر إنشاء مسار ملف المحرك.") }
                        FileOutputStream(output).use { out ->
                            while (true) {
                                val count = zip.read(buffer)
                                if (count < 0) break
                                extractedBytes += count
                                if (extractedBytes > 12L * 1024L * 1024L * 1024L) {
                                    throw IllegalStateException("الحجم المفكوك يتجاوز الحد الآمن البالغ 12 GB.")
                                }
                                out.write(buffer, 0, count)
                            }
                            out.fd.sync()
                        }
                    }
                    zip.closeEntry()
                }
            }
            val manifest = File(staging, "engine-manifest.json")
            if (!manifest.isFile || manifest.length() <= 0L || manifest.length() > 1024L * 1024L) {
                throw IllegalStateException("الحزمة لا تحتوي engine-manifest.json صالحًا أو أن حجمه يتجاوز 1 MB.")
            }
            val json = JSONObject(manifest.readText())
            if (!json.optBoolean("debugBuildSupported", false)) {
                throw IllegalStateException("حزمة المحرك لم تجتز اختبار بناء Flutter Debug حقيقي على Linux ARM64؛ ارفض تثبيتها واستخدم validate_and_pack.sh.")
            }
            if (json.has("releaseAotSupported") && json.opt("releaseAotSupported") !is Boolean) {
                throw IllegalStateException("حقل releaseAotSupported يجب أن يكون true أو false في بيان المحرك.")
            }
            // ZIP extraction does not preserve Unix executable mode bits.
            // The bundle publisher must provide an explicit, path-safe list.
            val executableList = File(staging, "engine-executables.txt")
            if (!executableList.isFile || executableList.length() <= 0L || executableList.length() > 8L * 1024L * 1024L) {
                throw IllegalStateException("الحزمة تفتقد engine-executables.txt أو أن حجمه يتجاوز الحد الآمن.")
            }
            val executablePaths = executableList.readLines()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
            if (executablePaths.isEmpty() || executablePaths.size > 100000 || executablePaths.distinct().size != executablePaths.size) {
                throw IllegalStateException("قائمة الملفات التنفيذية فارغة أو مكررة أو تتجاوز الحد الآمن.")
            }
            for (relative in executablePaths) {
                if (!relative.startsWith("runtime/") && !relative.startsWith("rootfs/")) {
                    throw SecurityException("قائمة الملفات التنفيذية يجب أن تقتصر على runtime/ وrootfs/.")
                }
                val executable = resolveInside(staging, relative)
                    ?: throw SecurityException("مسار تنفيذي غير آمن في engine-executables.txt.")
                if (!executable.isFile || (!executable.setExecutable(true, false) && !executable.canExecute())) {
                    throw IllegalStateException("تعذر استعادة صلاحية التنفيذ للملف: $relative")
                }
            }
            val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
            if (json.optInt("schemaVersion", -1) != 1 || json.optString("abi") != abi) {
                throw IllegalStateException("حزمة المحرك لا تطابق إصدار البيان أو معمارية هذا الهاتف ($abi).")
            }
            // Require every path to resolve inside staging before installation.
            val required = listOf("runtimeLauncher", "rootfsDirectory", "flutterExecutable", "javaExecutable", "androidSdkDirectory")
            val resolved = mutableMapOf<String, File>()
            for (key in required) {
                val candidate = resolveInside(staging, json.optString(key))
                    ?: throw IllegalStateException("مسار $key مفقود أو غير آمن في البيان.")
                if (!candidate.exists()) throw IllegalStateException("المورد المحدد في $key غير موجود داخل الحزمة.")
                resolved[key] = candidate
            }
            if (!resolved.getValue("runtimeLauncher").isFile ||
                !resolved.getValue("rootfsDirectory").isDirectory ||
                !resolved.getValue("flutterExecutable").isFile ||
                !resolved.getValue("javaExecutable").isFile ||
                !resolved.getValue("androidSdkDirectory").isDirectory) {
                throw IllegalStateException("أنواع الملفات في بيان المحرك غير مطابقة؛ تحقق من المشغل وRootFS وFlutter وJDK وSDK.")
            }
            val rootfs = resolved.getValue("rootfsDirectory").canonicalFile
            val rootfsPrefix = rootfs.path + File.separator
            for (key in listOf("flutterExecutable", "javaExecutable", "androidSdkDirectory")) {
                val candidate = resolved.getValue(key).canonicalFile
                if (!candidate.path.startsWith(rootfsPrefix)) {
                    throw SecurityException("يجب أن يقع مسار $key داخل نظام الملفات الجذري Linux.")
                }
            }
            if (!File(rootfs, "bin/sh").isFile || !File(rootfs, "bin/sh").canExecute()) {
                throw IllegalStateException("نظام Linux الجذري لا يحتوي /bin/sh قابلًا للتنفيذ.")
            }
            val sdk = resolved.getValue("androidSdkDirectory")
            if (!listOf("platforms", "build-tools", "platform-tools", "licenses", "cmdline-tools/latest/bin").all { File(sdk, it).isDirectory }) {
                throw IllegalStateException("Android SDK غير مكتمل؛ يلزم platforms وbuild-tools وplatform-tools وlicenses وcmdline-tools/latest/bin.")
            }
            val hasAndroidPlatform = File(sdk, "platforms").listFiles()?.any { platform ->
                platform.isDirectory && File(platform, "android.jar").isFile
            } == true
            if (!hasAndroidPlatform) throw IllegalStateException("Android SDK لا يحتوي منصة Android صالحة بملف android.jar.")
            if (!File(sdk, "cmdline-tools/latest/bin/sdkmanager").isFile) {
                throw IllegalStateException("Android SDK لا يحتوي sdkmanager داخل cmdline-tools/latest/bin.")
            }
            val hasArmBuildTools = File(sdk, "build-tools").listFiles()?.any { version ->
                version.isDirectory && listOf("aapt2", "aidl", "zipalign", "split-select", "apksigner").all { tool ->
                    File(version, tool).isFile
                }
            } == true
            if (!hasArmBuildTools) {
                throw IllegalStateException("لا توجد حزمة Build Tools كاملة قابلة للتنفيذ داخل Android SDK.")
            }
            val sdkManager = File(sdk, "cmdline-tools/latest/bin/sdkmanager")
            if (!sdkManager.setExecutable(true, false) && !sdkManager.canExecute()) {
                throw IllegalStateException("تعذر تفعيل أداة sdkmanager.")
            }
            for (version in File(sdk, "build-tools").listFiles().orEmpty().filter { it.isDirectory }) {
                for (tool in listOf("aapt2", "aidl", "zipalign", "split-select", "apksigner")) {
                    val executable = File(version, tool)
                    if (executable.isFile && !executable.setExecutable(true, false) && !executable.canExecute()) {
                        throw IllegalStateException("تعذر تفعيل أداة Android SDK: ${executable.name}.")
                    }
                }
            }
            for (key in listOf("runtimeLauncher", "flutterExecutable", "javaExecutable")) {
                val executable = resolved.getValue(key)
                if (!executable.setExecutable(true, false) && !executable.canExecute()) {
                    throw IllegalStateException("تعذر منح صلاحية التنفيذ للملف $key.")
                }
            }

            if (backup.exists()) backup.deleteRecursively()
            if (engineRoot.exists() && !engineRoot.renameTo(backup)) throw IllegalStateException("تعذر حفظ النسخة السابقة من المحرك.")
            if (!staging.renameTo(engineRoot)) {
                if (backup.exists()) backup.renameTo(engineRoot)
                throw IllegalStateException("تعذر تفعيل مجلد المحرك الجديد.")
            }
            if (backup.exists()) backup.deleteRecursively()
            File(engineRoot, "local-build-verification.json").delete()
            File(engineRoot, "local-build-debug-verification.json").delete()
            emitBuildEvent("تم تثبيت حزمة المحرك بعد التحقق من سلامتها؛ لا يزال اختبار إنتاج APK مطلوبًا.")
            return mapOf("success" to true, "message" to "تم تثبيت ملفات المحرك والتحقق من البصمة والبنية.", "bytes" to extractedBytes)
        } catch (error: Exception) {
            if (staging.exists()) staging.deleteRecursively()
            throw error
        }
    }

    /**
     * Streams a SAF project tree directly into app-private storage. This avoids
     * reading every source file into a Dart Uint8List before writing it again.
     */
    private fun stageProjectFromSaf(projectUri: String, projectName: String): File {
        val tree = Uri.parse(projectUri)
        if (!DocumentsContract.isTreeUri(tree)) {
            throw IllegalArgumentException("رابط مجلد المشروع لا يحمل صلاحية SAF الشجرية.")
        }
        val stagingRoot = File(filesDir, "bisho-local-builds").canonicalFile
        if (!stagingRoot.exists() && !stagingRoot.mkdirs()) {
            throw IllegalStateException("تعذر إنشاء مساحة البناء المحلية.")
        }
        val safeName = projectName.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80).ifBlank { "project" }
        val destination = File(stagingRoot, "${System.currentTimeMillis()}_${safeName}").canonicalFile
        if (!destination.path.startsWith(stagingRoot.path + File.separator) || !destination.mkdirs()) {
            throw IllegalStateException("تعذر إنشاء مجلد مرحلي آمن للمشروع.")
        }
        stagingCancelled = false
        var fileCount = 0
        var totalBytes = 0L
        val maxFiles = 20_000
        val maxBytes = 1024L * 1024L * 1024L
        val buffer = ByteArray(256 * 1024)
        val skipped = setOf(".git", ".dart_tool", "build", ".idea")

        fun copyDirectory(parentDocumentId: String, targetDirectory: File, depth: Int) {
            if (stagingCancelled) throw InterruptedException("تم إلغاء تجهيز ملفات المشروع.")
            if (depth > 64) throw IllegalStateException("تجاوز عمق مجلدات المشروع الحد المسموح.")
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentDocumentId)
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                ),
                null, null, null
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                if (idColumn < 0 || nameColumn < 0 || mimeColumn < 0) {
                    throw IllegalStateException("مزود التخزين لا يعيد بيانات الملفات المطلوبة.")
                }
                while (cursor.moveToNext()) {
                    if (stagingCancelled) throw InterruptedException("تم إلغاء تجهيز ملفات المشروع.")
                    val name = cursor.getString(nameColumn)?.trim().orEmpty()
                    if (name.isBlank() || name == "." || name == ".." || name.contains('/') || name.contains('\\') || name.contains('\u0000') || name.any { it.code < 32 || it.code == 127 }) {
                        throw SecurityException("اسم عنصر غير آمن داخل مجلد المشروع.")
                    }
                    if (skipped.contains(name)) continue
                    val documentId = cursor.getString(idColumn)
                    val mime = cursor.getString(mimeColumn)
                    val target = File(targetDirectory, name).canonicalFile
                    if (!target.path.startsWith(targetDirectory.canonicalPath + File.separator) || target.exists()) {
                        throw SecurityException("تم اكتشاف مسار خارج المشروع أو اسم ملف مكرر: $name")
                    }
                    val source = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (!target.mkdirs()) throw IllegalStateException("تعذر إنشاء المجلد: $name")
                        copyDirectory(documentId, target, depth + 1)
                    } else {
                        fileCount++
                        if (fileCount > maxFiles) throw IllegalStateException("المشروع يحتوي على أكثر من 20,000 ملف.")
                        contentResolver.openInputStream(source)?.use { input ->
                            FileOutputStream(target).use { output ->
                                while (true) {
                                    if (stagingCancelled) throw InterruptedException("تم إلغاء تجهيز ملفات المشروع.")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    totalBytes += count
                                    if (totalBytes > maxBytes) throw IllegalStateException("حجم المشروع يتجاوز حد النسخ المحلي البالغ 1 GB.")
                                    output.write(buffer, 0, count)
                                }
                                output.fd.sync()
                            }
                        } ?: throw IllegalStateException("تعذرت قراءة الملف من مساحة التخزين: $name")
                        if (fileCount % 100 == 0) {
                            emitBuildEvent("جارٍ تجهيز المشروع: $fileCount ملفًا، ${totalBytes / (1024 * 1024)} MB...")
                        }
                    }
                }
            } ?: throw IllegalStateException("تعذر قراءة محتويات مجلد المشروع من مزود التخزين.")
        }

        try {
            val treeId = DocumentsContract.getTreeDocumentId(tree)
            emitBuildEvent("جارٍ نسخ ملفات المشروع مباشرة إلى مساحة التطبيق دون تحميلها كاملة إلى الذاكرة...")
            copyDirectory(treeId, destination, 0)
            if (!File(destination, "pubspec.yaml").isFile) {
                throw IllegalArgumentException("المجلد المحدد لا يحتوي pubspec.yaml؛ اختر جذر مشروع Flutter.")
            }
            emitBuildEvent("اكتمل تجهيز $fileCount ملفًا بحجم ${totalBytes / (1024 * 1024)} MB.")
            return destination
        } catch (error: Exception) {
            destination.deleteRecursively()
            throw error
        } finally {
            stagingCancelled = false
        }
    }

    /** Copies a potentially large APK to the selected SAF tree without buffering it in Dart memory. */
    private fun saveArtifactToSaf(artifactPath: String, parentUri: String, fileName: String): Pair<String, Long> {
        if (fileName.isBlank() || fileName.contains("/") || fileName.contains("\\") || fileName == "." || fileName == "..") {
            throw IllegalArgumentException("اسم ملف APK غير صالح.")
        }
        val source = File(artifactPath).canonicalFile
        val stagingRoot = File(filesDir, "bisho-local-builds").canonicalFile
        val artifactRoot = File(filesDir, "bisho-local-build-artifacts").canonicalFile
        val fromStaging = source.path.startsWith(stagingRoot.path + File.separator)
        val fromArtifacts = source.path.startsWith(artifactRoot.path + File.separator)
        if ((!fromStaging && !fromArtifacts) || !source.isFile || source.length() <= 0L ||
            !source.name.endsWith(".apk", true)) {
            throw IllegalArgumentException("ملف APK خارج مساحات البناء الآمنة أو غير صالح.")
        }
        val tree = Uri.parse(parentUri)
        if (!DocumentsContract.isTreeUri(tree)) {
            throw IllegalArgumentException("رابط مجلد المشروع لا يحمل صلاحية SAF الشجرية المطلوبة.")
        }
        val treeId = DocumentsContract.getTreeDocumentId(tree)
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
        val temporaryName = "${fileName}.pending-${System.currentTimeMillis()}"
        val target = DocumentsContract.createDocument(contentResolver, parent, "application/vnd.android.package-archive", temporaryName)
            ?: throw IllegalStateException("رفض مزود التخزين إنشاء ملف APK مؤقت.")
        var copied = 0L
        try {
            FileInputStream(source).use { input ->
                contentResolver.openOutputStream(target, "w")?.use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        copied += count
                    }
                    output.flush()
                } ?: throw IllegalStateException("تعذر فتح ملف الوجهة للكتابة.")
            }
            if (copied != source.length()) throw IllegalStateException("حجم APK المنسوخ لا يطابق الملف الأصلي.")

            // Preserve the previous APK until the new copy is complete.
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, treeId)
            var previous: Uri? = null
            contentResolver.query(childrenUri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    if (nameIndex >= 0 && cursor.getString(nameIndex) == fileName && idIndex >= 0) {
                        previous = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(idIndex))
                        break
                    }
                }
            }
            val previousBackup = previous?.let {
                DocumentsContract.renameDocument(contentResolver, it, "${fileName}.previous-${System.currentTimeMillis()}")
                    ?: throw IllegalStateException("تعذر حفظ نسخة APK السابقة قبل الاستبدال.")
            }
            val renamed = try {
                DocumentsContract.renameDocument(contentResolver, target, fileName)
                    ?: throw IllegalStateException("تم نسخ APK لكن تعذر اعتماد اسمه النهائي.")
            } catch (error: Exception) {
                if (previousBackup != null) {
                    try { DocumentsContract.renameDocument(contentResolver, previousBackup, fileName) } catch (_: Exception) {}
                }
                throw error
            }
            if (previousBackup != null) {
                try { DocumentsContract.deleteDocument(contentResolver, previousBackup) } catch (_: Exception) {}
            }
            return Pair(renamed.toString(), copied)
        } catch (error: Exception) {
            try { DocumentsContract.deleteDocument(contentResolver, target) } catch (_: Exception) {}
            throw error
        }
    }

    private fun emitBuildEvent(message: String, isError: Boolean = false) {
        runOnUiThread {
            buildEventSink?.success(mapOf("message" to message, "isError" to isError))
        }
    }

    private fun executeLocalBuild(projectPath: String, buildMode: String, result: MethodChannel.Result) {
        var process: Process? = null
        try {
            val project = File(projectPath).canonicalFile
            val freeBeforeBuild = StatFs(filesDir.absolutePath).availableBytes
            if (freeBeforeBuild < minimumBuildStorageBytes) {
                throw IllegalStateException("المساحة الحرة غير كافية للبناء المحلي؛ يلزم توفير 5 GB على الأقل لمساحة Gradle وملفات البناء المؤقتة.")
            }
            val stagingRoot = File(filesDir, "bisho-local-builds").canonicalFile
            // The staging folder is app-private. Reject arbitrary paths supplied
            // over the platform channel before invoking any executable.
            if (!project.path.startsWith(stagingRoot.path + File.separator) ||
                !File(project, "pubspec.yaml").isFile) {
                throw IllegalArgumentException("مجلد المشروع المرحّل غير صالح أو لا يحتوي pubspec.yaml.")
            }
            prepareAndroidGradleWrapper(project)

            val engineDirectory = File(filesDir, "bisho-local-build-engine").canonicalFile
            val manifest = File(engineDirectory, "engine-manifest.json")
            if (!manifest.isFile || manifest.length() == 0L || manifest.length() > 1024L * 1024L) {
                throw IllegalStateException("بيان محرك البناء غير موجود أو يتجاوز الحجم الآمن.")
            }
            val json = JSONObject(manifest.readText())
            if (json.optInt("schemaVersion", -1) != 1 ||
                json.optString("abi") != (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")) {
                throw IllegalStateException("بيان محرك البناء غير متوافق مع هذا الجهاز.")
            }
            val launcher = resolveInside(engineDirectory, json.optString("runtimeLauncher"))
            val rootfs = resolveInside(engineDirectory, json.optString("rootfsDirectory"))
            if (launcher == null || !launcher.isFile || !launcher.canExecute() ||
                rootfs == null || !rootfs.isDirectory) {
                throw IllegalStateException("مشغل Linux أو نظام الملفات الجذري غير مكتمل.")
            }
            val rootfsRelative = json.optString("rootfsDirectory").trimEnd('/')
            fun guestPath(key: String): String {
                val relative = json.optString(key).replace('\\', '/')
                if (relative.isBlank() || relative.startsWith('/') ||
                    relative.split('/').any { it.isBlank() || it == "." || it == ".." } ||
                    (relative != rootfsRelative && !relative.startsWith("$rootfsRelative/"))) {
                    throw IllegalStateException("مسار $key غير آمن أو لا يقع داخل نظام الملفات الجذري.")
                }
                val guest = "/" + relative.removePrefix(rootfsRelative).trimStart('/')
                if (!guest.matches(Regex("/[A-Za-z0-9_./+-]+"))) {
                    throw IllegalStateException("يحتوي مسار $key على محارف غير مدعومة.")
                }
                return guest
            }
            fun shellQuote(value: String): String = "'$value'"
            val flutterGuest = guestPath("flutterExecutable")
            val javaGuest = guestPath("javaExecutable")
            val sdkGuest = guestPath("androidSdkDirectory")
            val javaBin = javaGuest.substringBeforeLast('/')
            val javaHome = javaBin.substringBeforeLast('/')
            val sdkPath = sdkGuest
            val flutterBin = flutterGuest.substringBeforeLast('/')
            val sdkTools = "$sdkPath/cmdline-tools/latest/bin"
            val sdkPlatformTools = "$sdkPath/platform-tools"
            val flutterRoot = flutterGuest.substringBeforeLast("/bin/")
            val releaseAotCertified = json.optBoolean("releaseAotSupported", false)
            val aotPreflight = if (buildMode == "release") {
                if (!releaseAotCertified) {
                    throw IllegalStateException("هذه الحزمة اجتازت اختبار Debug فقط ولم تجتز اختبار Release/AOT كاملًا عند تجهيزها؛ اختر Debug أو ثبّت حزمة محرك معتمدة لـ Release.")
                }
                "test -x ${shellQuote("$flutterRoot/bin/cache/artifacts/engine/android-arm64-release/linux-arm64/gen_snapshot")} || { echo 'بيان الحزمة يعلن Release/AOT لكن gen_snapshot غير موجود؛ أُوقف البناء.' >&2; exit 78; }; "
            } else ""
            val flutterBuildArgs = if (buildMode == "release") "--release" else "--debug"
            val apkRelativePath = if (buildMode == "release") {
                "build/app/outputs/flutter-apk/app-release.apk"
            } else {
                "build/app/outputs/flutter-apk/app-debug.apk"
            }
            val persistentHome = File(filesDir, "bisho-local-build-home").apply {
                if (!exists() && !mkdirs()) throw IllegalStateException("تعذر إنشاء مساحة ذاكرة البناء المحلية.")
            }.canonicalFile
            val command = mutableListOf(
                launcher.absolutePath, "-0", "-r", rootfs.absolutePath,
                "-b", "${project.absolutePath}:/workspace/project",
                "-b", "${persistentHome.absolutePath}:/bisho-home",
                "-w", "/workspace/project", "/bin/sh", "-lc",
                "set -eu; export HOME=/bisho-home; export PUB_CACHE=/bisho-home/.pub-cache; export GRADLE_USER_HOME=/bisho-home/.gradle; " +
                    "export JAVA_HOME=${shellQuote(javaHome)}; export ANDROID_HOME=${shellQuote(sdkPath)}; " +
                    "export ANDROID_SDK_ROOT=${shellQuote(sdkPath)}; export PATH=${shellQuote("$flutterBin:$javaBin:$sdkTools:$sdkPlatformTools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")}; " +
                    "test -x ${shellQuote(flutterGuest)}; test -x ${shellQuote(javaGuest)}; " +
                    "test -d ${shellQuote("$sdkPath/platforms")}; test -d ${shellQuote("$sdkPath/build-tools")}; " +
                    "TOOLS=; for candidate in $(printf '%s\n' ${shellQuote(sdkPath)}/build-tools/* | sort -Vr); do " +
                    "if [ -x \"\$candidate/aapt2\" ] && [ -x \"\$candidate/aidl\" ] && [ -x \"\$candidate/zipalign\" ] && [ -x \"\$candidate/split-select\" ] && [ -x \"\$candidate/apksigner\" ]; then TOOLS=\"\$candidate\"; break; fi; done; " +
                    "test -n \"\$TOOLS\"; \"\$TOOLS/aapt2\" version; \"\$TOOLS/aidl\" --version; \"\$TOOLS/apksigner\" version; " +
                    "\"\$TOOLS/zipalign\" -h >/dev/null 2>&1 || test \$? -eq 1; " +
                    "mkdir -p /bisho-home/.gradle; MEM_KB=0; if [ -r /proc/meminfo ]; then MEM_KB=$(awk '/MemTotal/ {print \$2}' /proc/meminfo); fi; " +
                    "GRADLE_XMX=1024m; if [ \"\$MEM_KB\" -ge 6000000 ]; then GRADLE_XMX=1536m; fi; " +
                    "touch /bisho-home/.gradle/gradle.properties; " +
                    "set_gradle_property() { KEY=\$1; VALUE=\$2; if grep -q \"^\$KEY=\" /bisho-home/.gradle/gradle.properties; then sed -i \"s|^\$KEY=.*|\$KEY=\$VALUE|\" /bisho-home/.gradle/gradle.properties; else printf '%s=%s\n' \"\$KEY\" \"\$VALUE\" >> /bisho-home/.gradle/gradle.properties; fi; }; " +
                    "set_gradle_property org.gradle.jvmargs \"-Xmx\$GRADLE_XMX -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8\"; " +
                    "set_gradle_property org.gradle.workers.max 2; set_gradle_property org.gradle.parallel false; " +
                    "set_gradle_property org.gradle.caching true; set_gradle_property kotlin.daemon.jvmargs -Xmx512m; " +
                    "export FLUTTER_SUPPRESS_ANALYTICS=true; export CI=true; export PUB_ENVIRONMENT=bisho_ide; export JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=2'; " +
                    "if grep -q '^android.aapt2FromMavenOverride=' /bisho-home/.gradle/gradle.properties 2>/dev/null; then " +
                    "sed -i \"s|^android.aapt2FromMavenOverride=.*|android.aapt2FromMavenOverride=\$TOOLS/aapt2|\" /bisho-home/.gradle/gradle.properties; " +
                    "else printf 'android.aapt2FromMavenOverride=%s\n' \"\$TOOLS/aapt2\" >> /bisho-home/.gradle/gradle.properties; fi; " +
                    "${shellQuote(flutterGuest)} --version; ${shellQuote(javaGuest)} -version; " +
                    "${shellQuote(flutterGuest)} precache --android; " +
                    aotPreflight +
                    "rm -f /workspace/project/${apkRelativePath}; " +
                    "${shellQuote(flutterGuest)} pub get; ${shellQuote(flutterGuest)} build apk --no-pub --target-platform android-arm64 $flutterBuildArgs; " +
                    "APK=/workspace/project/${apkRelativePath}; test -s \"\$APK\"; " +
                    "test -x \"\$TOOLS/apksigner\"; \"\$TOOLS/apksigner\" verify --verbose \"\$APK\""
            )
            // PRoot builds often need proc/dev for Java and Android build tools.
            for (hostPath in listOf("/dev", "/proc")) {
                if (File(hostPath).exists()) {
                    command.addAll(4, listOf("-b", hostPath))
                }
            }
            emitBuildEvent("تم تجهيز المشروع. فحص Flutter وJava وAndroid SDK ثم بدء البناء...")
            val runningBuild = ProcessBuilder(command).redirectErrorStream(true).apply {
                environment()["HOME"] = persistentHome.absolutePath
            }.start()
            process = runningBuild
            activeBuildProcess = runningBuild
            val exitCode = waitForBuildProcess(runningBuild, 60, TimeUnit.MINUTES, "البناء المحلي")
            if (exitCode != 0) throw IllegalStateException("فشل Flutter build برمز خروج $exitCode. راجع سجل البناء.")
            val apk = File(project, apkRelativePath)
            if (!apk.isFile || apk.length() < 64L * 1024L) {
                throw IllegalStateException("لم ينتج البناء ملف APK بالحجم المتوقع؛ الملف مفقود أو أصغر من الحد الأدنى.")
            }
            // Verify the actual artifact, not only the Flutter process exit code.
            val verifyScript =
                "set -eu; export JAVA_HOME=${shellQuote(javaHome)}; export PATH=${shellQuote("$javaBin:$sdkTools:$sdkPlatformTools:/usr/local/bin:/usr/bin:/bin")}; " +
                "TOOLS=; for candidate in $(printf '%s\n' ${shellQuote(sdkPath)}/build-tools/* | sort -Vr); do " +
                "if [ -x \"\$candidate/aapt2\" ] && [ -x \"\$candidate/aidl\" ] && [ -x \"\$candidate/zipalign\" ] && [ -x \"\$candidate/split-select\" ] && [ -x \"\$candidate/apksigner\" ]; then TOOLS=\"\$candidate\"; break; fi; done; " +
                "test -n \"\$TOOLS\"; \"\$TOOLS/apksigner\" verify --verbose /workspace/project/${apkRelativePath}; \"\$TOOLS/zipalign\" -c -v 4 /workspace/project/${apkRelativePath}"
            val verifyCommand = mutableListOf(
                launcher.absolutePath, "-0", "-r", rootfs.absolutePath,
                "-b", "${project.absolutePath}:/workspace/project",
                "/bin/sh", "-lc", verifyScript
            )
            for (hostPath in listOf("/dev", "/proc")) {
                if (File(hostPath).exists()) verifyCommand.addAll(4, listOf("-b", hostPath))
            }
            emitBuildEvent("تم إنتاج APK. جارٍ التحقق من التوقيع ومحاذاة ZIP...")
            val verifyProcess = ProcessBuilder(verifyCommand).redirectErrorStream(true).start()
            activeBuildProcess = verifyProcess
            val verifyExit = waitForBuildProcess(verifyProcess, 3, TimeUnit.MINUTES, "التحقق من APK")
            if (verifyExit != 0) throw IllegalStateException("تم إنتاج APK لكن فشل التحقق من توقيعه أو محاذاته (رمز $verifyExit).")

            // Keep a verified copy outside the temporary staged project. The UI
            // removes the staging tree after SAF export; readiness must not then
            // point at an artifact that has already been deleted.
            val artifactRoot = File(filesDir, "bisho-local-build-artifacts").canonicalFile
            if (!artifactRoot.exists() && !artifactRoot.mkdirs()) {
                throw IllegalStateException("تعذر إنشاء مساحة حفظ APK داخل التطبيق.")
            }
            val artifactName = "bisho-${buildMode}-${System.currentTimeMillis()}.apk"
            val artifactTemp = File(artifactRoot, "$artifactName.pending")
            val retainedArtifact = File(artifactRoot, artifactName)
            FileInputStream(apk).use { input ->
                FileOutputStream(artifactTemp).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            if (artifactTemp.length() != apk.length() || !artifactTemp.renameTo(retainedArtifact)) {
                artifactTemp.delete()
                throw IllegalStateException("تعذر حفظ نسخة APK الموثقة داخل مساحة التطبيق.")
            }
            val artifactSha256 = sha256File(retainedArtifact)

            // Persist separate Debug and Release proof tied to the exact retained
            // APK bytes, its path, and the installed engine manifest digest.
            val verificationName = if (buildMode == "release") "local-build-verification.json" else "local-build-debug-verification.json"
            val verification = File(engineDirectory, verificationName)
            val verificationTemp = File(engineDirectory, "$verificationName.tmp")
            verificationTemp.writeText(
                JSONObject()
                    .put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
                    .put("mode", buildMode)
                    .put("verifiedAt", System.currentTimeMillis())
                    .put("apkBytes", retainedArtifact.length())
                    .put("artifactPath", retainedArtifact.absolutePath)
                    .put("artifactSha256", artifactSha256)
                    .put("manifestSha256", sha256File(manifest))
                    .put("flutterExecutable", json.optString("flutterExecutable"))
                    .put("signatureVerified", true)
                    .put("zipAligned", true)
                    .toString()
            )
            if (verification.exists() && !verification.delete()) throw IllegalStateException("تعذر تحديث سجل تحقق البناء المحلي.")
            if (!verificationTemp.renameTo(verification)) throw IllegalStateException("تعذر اعتماد سجل تحقق البناء المحلي.")
            // Retain only the newest three artifacts per mode to cap private storage.
            artifactRoot.listFiles()?.filter { it.isFile && it.name.startsWith("bisho-$buildMode-") && it.name.endsWith(".apk") }
                ?.sortedByDescending { it.lastModified() }?.drop(3)?.forEach { it.delete() }
            runOnUiThread { result.success(mapOf("success" to true, "artifactPath" to retainedArtifact.absolutePath, "message" to "اكتمل البناء المحلي.")) }
            emitBuildEvent("اكتمل بناء $buildMode APK وحُفظت نسخة موثقة: ${retainedArtifact.length()} bytes")
        } catch (error: Exception) {
            emitBuildEvent(error.message ?: "حدث خطأ أثناء البناء المحلي.", true)
            runOnUiThread { result.success(mapOf("success" to false, "message" to (error.message ?: "فشل البناء المحلي."))) }
        } finally {
            activeBuildProcess = null
        }
    }

    /**
     * SAF copies file contents, not POSIX mode bits. Flutter invokes the Android
     * Gradle wrapper during `flutter build`; without restoring +x, a perfectly
     * valid project copied from Documents can fail with Permission denied.
     * Also normalize CRLF so the wrapper's /usr/bin/env shebang remains usable
     * in the Linux guest.
     */
    private fun prepareAndroidGradleWrapper(project: File) {
        val androidDirectory = File(project, "android").canonicalFile
        if (!androidDirectory.isDirectory ||
            !androidDirectory.path.startsWith(project.canonicalPath + File.separator)) {
            throw IllegalStateException("مجلد android غير موجود في مشروع Flutter؛ لا يمكن تشغيل Gradle محليًا.")
        }
        val wrapper = File(androidDirectory, "gradlew").canonicalFile
        if (!wrapper.path.startsWith(androidDirectory.path + File.separator) ||
            !wrapper.isFile || wrapper.length() <= 0L || wrapper.length() > 2L * 1024L * 1024L) {
            throw IllegalStateException("ملف android/gradlew مفقود أو غير صالح؛ أعد إنشاء ملفات Android الأساسية للمشروع.")
        }
        val wrapperJar = File(androidDirectory, "gradle/wrapper/gradle-wrapper.jar").canonicalFile
        val wrapperProperties = File(androidDirectory, "gradle/wrapper/gradle-wrapper.properties").canonicalFile
        if (!wrapperJar.path.startsWith(androidDirectory.path + File.separator) ||
            !wrapperJar.isFile || wrapperJar.length() < 1024L) {
            throw IllegalStateException("ملف Gradle Wrapper JAR مفقود أو تالف داخل android/gradle/wrapper.")
        }
        if (!wrapperProperties.path.startsWith(androidDirectory.path + File.separator) ||
            !wrapperProperties.isFile || wrapperProperties.length() <= 0L || wrapperProperties.length() > 64L * 1024L) {
            throw IllegalStateException("ملف gradle-wrapper.properties مفقود أو غير صالح.")
        }
        val properties = wrapperProperties.readText()
        val distribution = Regex("(?m)^\\s*distributionUrl\\s*=\\s*([^\\s]+)\\s*$")
            .find(properties)?.groupValues?.get(1)?.replace("\\:", ":")
            ?: throw IllegalStateException("ملف Gradle Wrapper لا يحتوي distributionUrl صالحًا.")
        if (!(distribution.startsWith("https://", ignoreCase = true) ||
                distribution.startsWith("file:/", ignoreCase = true))) {
            throw SecurityException("رابط تنزيل Gradle يجب أن يستخدم HTTPS أو ملفًا محليًا داخل بيئة البناء.")
        }
        val original = wrapper.readText()
        if (original.startsWith("#!") && original.contains("\r")) {
            val normalized = original.replace("\r\n", "\n").replace("\r", "\n")
            wrapper.writeText(normalized)
        }
        if (!wrapper.setExecutable(true, false) && !wrapper.canExecute()) {
            throw IllegalStateException("تعذر استعادة صلاحية التنفيذ لملف android/gradlew بعد نسخ المشروع من التخزين.")
        }
        emitBuildEvent("تم تجهيز Gradle Wrapper: تصحيح صلاحية التنفيذ وفحص ملفات wrapper.")
    }

    private fun waitForBuildProcess(
        process: Process,
        timeout: Long,
        unit: TimeUnit,
        operation: String
    ): Int {
        val outputThread = Thread {
            try {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        emitBuildEvent(line.take(2000), line.contains("error", true) || line.contains("FAIL", true))
                    }
                }
            } catch (error: Exception) {
                emitBuildEvent("تعذر قراءة سجل $operation: ${error.message ?: "خطأ إدخال/إخراج"}", true)
            }
        }.apply { name = "bisho-$operation-output"; isDaemon = true; start() }
        val completed = waitForProcessWithTimeout(process, timeout, unit)
        if (!completed) {
            process.destroyForcibly()
            outputThread.join(5000)
            throw IllegalStateException("انتهت مهلة $operation؛ أوقف Bisho IDE عملية PRoot بعد انتهاء الوقت المحدد.")
        }
        outputThread.join(10000)
        return process.exitValue()
    }

    /**
     * Execute a complete throwaway Flutter Android Debug build inside PRoot.
     * Tool version output alone is not proof that Gradle, AAPT2, Java, and the
     * Android platform can cooperate to produce a usable APK on this device.
     */
    private fun probeLocalBuildEngine(): Map<String, Any> {
        val engineDirectory = File(filesDir, "bisho-local-build-engine").canonicalFile
        val manifest = File(engineDirectory, "engine-manifest.json")
        if (!manifest.isFile || manifest.length() <= 0L || manifest.length() > 1024L * 1024L) {
            return mapOf("success" to false, "message" to "بيان المحرك غير موجود أو غير صالح.")
        }
        val json = JSONObject(manifest.readText())
        if (json.optInt("schemaVersion", -1) != 1 || json.optString("abi") != (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")) {
            return mapOf("success" to false, "message" to "بيان المحرك لا يطابق معمارية الهاتف.")
        }
        if (!json.optBoolean("debugBuildSupported", false)) {
            return mapOf("success" to false, "message" to "بيان المحرك لا يحمل اعتماد اختبار Debug من أداة تجهيز الحزمة؛ أعد تجهيز المحرك بعد نجاح smoke build على Linux ARM64.")
        }
        val launcher = resolveInside(engineDirectory, json.optString("runtimeLauncher"))
        val rootfs = resolveInside(engineDirectory, json.optString("rootfsDirectory"))
        val flutter = resolveInside(engineDirectory, json.optString("flutterExecutable"))
        val java = resolveInside(engineDirectory, json.optString("javaExecutable"))
        val sdk = resolveInside(engineDirectory, json.optString("androidSdkDirectory"))
        if (launcher == null || rootfs == null || flutter == null || java == null || sdk == null ||
            !launcher.isFile || !rootfs.isDirectory || !flutter.isFile || !java.isFile || !sdk.isDirectory ||
            !launcher.canExecute() || !flutter.canExecute() || !java.canExecute() ||
            !File(rootfs, "bin/sh").let { it.isFile && it.canExecute() }) {
            return mapOf("success" to false, "message" to "ملفات تشغيل المحرك غير مكتملة أو غير قابلة للتنفيذ.")
        }
        val rootfsRelative = json.optString("rootfsDirectory").trimEnd('/')
        fun guestPath(fileKey: String): String {
            val relative = json.optString(fileKey).replace('\\', '/')
            if (relative.isBlank() || relative.startsWith('/') ||
                relative.split('/').any { it.isBlank() || it == "." || it == ".." } ||
                (relative != rootfsRelative && !relative.startsWith("$rootfsRelative/"))) {
                throw IllegalStateException("مسار $fileKey غير آمن أو خارج RootFS.")
            }
            val guest = "/" + relative.removePrefix(rootfsRelative).trimStart('/')
            if (!guest.matches(Regex("/[A-Za-z0-9_./+-]+"))) throw IllegalStateException("مسار $fileKey يحتوي محارف غير مدعومة.")
            return guest
        }
        val flutterGuest = guestPath("flutterExecutable")
        val javaGuest = guestPath("javaExecutable")
        val sdkGuest = guestPath("androidSdkDirectory")
        val javaBin = javaGuest.substringBeforeLast('/')
        val javaHome = javaBin.substringBeforeLast('/')
        val flutterBin = flutterGuest.substringBeforeLast('/')
        val smokeRoot = File(cacheDir, "bisho-engine-smoke").canonicalFile
        val persistentHome = File(filesDir, "bisho-local-build-home").canonicalFile
        val artifactRoot = File(filesDir, "bisho-local-build-artifacts").canonicalFile
        if (smokeRoot.exists() && !smokeRoot.deleteRecursively()) {
            throw IllegalStateException("تعذر تنظيف مساحة اختبار المحرك السابقة.")
        }
        if (!smokeRoot.mkdirs()) throw IllegalStateException("تعذر إنشاء مساحة اختبار المحرك.")
        if (!persistentHome.exists() && !persistentHome.mkdirs()) throw IllegalStateException("تعذر إنشاء ذاكرة البناء المحلية.")
        val projectHost = File(smokeRoot, "project")
        if (!projectHost.mkdirs()) throw IllegalStateException("تعذر إنشاء مشروع Flutter التجريبي.")
        val gradleProperties = File(persistentHome, ".gradle/gradle.properties")
        gradleProperties.parentFile?.let { if (!it.exists() && !it.mkdirs()) throw IllegalStateException("تعذر إنشاء إعدادات Gradle.") }
        val script = """
            set -eu
            export HOME=/bisho-home
            export PUB_CACHE=/bisho-home/.pub-cache
            export GRADLE_USER_HOME=/bisho-home/.gradle
            export JAVA_HOME='${javaHome}'
            export ANDROID_HOME='${sdkGuest}'
            export ANDROID_SDK_ROOT='${sdkGuest}'
            export FLUTTER_SUPPRESS_ANALYTICS=true
            export CI=true
            export JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=2'
            export PATH='${flutterBin}:${javaBin}:${sdkGuest}/cmdline-tools/latest/bin:${sdkGuest}/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
            test -x '${flutterGuest}'
            test -x '${javaGuest}'
            test -s '${sdkGuest}/licenses/android-sdk-license'
            test -d '${sdkGuest}/platforms'
            test -d '${sdkGuest}/build-tools'
            TOOLS=
            for candidate in ${'$'}(printf '%s\n' '${sdkGuest}'/build-tools/* | sort -Vr); do
              if [ -x "${'$'}candidate/aapt2" ] && [ -x "${'$'}candidate/aidl" ] && [ -x "${'$'}candidate/zipalign" ] && [ -x "${'$'}candidate/split-select" ] && [ -x "${'$'}candidate/apksigner" ]; then TOOLS="${'$'}candidate"; break; fi
            done
            test -n "${'$'}TOOLS"
            mkdir -p /bisho-home/.gradle
            touch /bisho-home/.gradle/gradle.properties
            if grep -q '^android.aapt2FromMavenOverride=' /bisho-home/.gradle/gradle.properties; then
              sed -i "s|^android.aapt2FromMavenOverride=.*|android.aapt2FromMavenOverride=${'$'}TOOLS/aapt2|" /bisho-home/.gradle/gradle.properties
            else
              printf 'android.aapt2FromMavenOverride=%s\n' "${'$'}TOOLS/aapt2" >> /bisho-home/.gradle/gradle.properties
            fi
            '${flutterGuest}' --version
            '${javaGuest}' -version
            '${sdkGuest}/cmdline-tools/latest/bin/sdkmanager' --version
            '${flutterGuest}' precache --android
            '${flutterGuest}' create --platforms=android --project-name bisho_engine_smoke --no-pub /bisho-engine-smoke/project
            cd /bisho-engine-smoke/project
            '${flutterGuest}' pub get
            '${flutterGuest}' build apk --debug --target-platform android-arm64
            APK=build/app/outputs/flutter-apk/app-debug.apk
            test -s "${'$'}APK"
            "${'$'}TOOLS/apksigner" verify --verbose "${'$'}APK"
            "${'$'}TOOLS/zipalign" -c -v 4 "${'$'}APK"
        """.trimIndent()
        val command = mutableListOf(
            launcher.absolutePath, "-0", "-r", rootfs.absolutePath,
            "-b", "${smokeRoot.absolutePath}:/bisho-engine-smoke",
            "-b", "${persistentHome.absolutePath}:/bisho-home",
            "/bin/sh", "-lc", script
        )
        for (hostPath in listOf("/dev", "/proc")) {
            if (File(hostPath).exists()) command.addAll(4, listOf("-b", hostPath))
        }
        val log = File(cacheDir, "bisho-engine-probe-${System.currentTimeMillis()}.log")
        return try {
            emitBuildEvent("بدأ اختبار البناء الحقيقي: إنشاء مشروع Flutter تجريبي داخل المحرك...")
            val process = ProcessBuilder(command).redirectErrorStream(true).start()
            activeBuildProcess = process
            val outputThread = Thread {
                try {
                    FileOutputStream(log).use { sink ->
                        process.inputStream.bufferedReader().useLines { lines ->
                            lines.forEach { line ->
                                sink.write((line + "\n").toByteArray(Charsets.UTF_8))
                                sink.flush()
                                emitBuildEvent(line.take(2000), line.contains("error", true) || line.contains("FAIL", true))
                            }
                        }
                    }
                } catch (error: Exception) {
                    emitBuildEvent("تعذر قراءة سجل اختبار المحرك: ${error.message ?: "خطأ إدخال/إخراج"}", true)
                }
            }.apply { name = "bisho-engine-smoke-output"; isDaemon = true; start() }
            val completed = waitForProcessWithTimeout(process, 60, TimeUnit.MINUTES)
            if (!completed) process.destroyForcibly()
            outputThread.join(10000)
            if (!completed) {
                mapOf("success" to false, "message" to "انتهت مهلة اختبار بناء Debug التجريبي بعد 60 دقيقة. راجع السجل.", "log" to readProbeLog(log))
            } else if (process.exitValue() != 0) {
                mapOf("success" to false, "message" to "فشل بناء Flutter Debug التجريبي داخل PRoot (رمز ${process.exitValue()}). لم يتم اعتماد المحرك.", "log" to readProbeLog(log))
            } else {
                val apk = File(projectHost, "build/app/outputs/flutter-apk/app-debug.apk")
                if (!apk.isFile || apk.length() < 64L * 1024L) {
                    throw IllegalStateException("اكتمل أمر Flutter دون APK تجريبي صالح بالحجم المتوقع.")
                }
                if (!artifactRoot.exists() && !artifactRoot.mkdirs()) throw IllegalStateException("تعذر إنشاء مساحة حفظ APK التجريبي.")
                val retained = File(artifactRoot, "bisho-debug-engine-smoke-${System.currentTimeMillis()}.apk")
                val temp = File(artifactRoot, "${retained.name}.pending")
                FileInputStream(apk).use { input ->
                    FileOutputStream(temp).use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                        output.fd.sync()
                    }
                }
                if (temp.length() != apk.length() || !temp.renameTo(retained)) {
                    temp.delete()
                    throw IllegalStateException("تعذر حفظ APK اختبار المحرك داخل مساحة التطبيق.")
                }
                val proofName = "local-build-debug-verification.json"
                val proof = File(engineDirectory, proofName)
                val proofTemp = File(engineDirectory, "$proofName.tmp")
                proofTemp.writeText(
                    JSONObject()
                        .put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
                        .put("mode", "debug")
                        .put("verifiedAt", System.currentTimeMillis())
                        .put("apkBytes", retained.length())
                        .put("artifactPath", retained.absolutePath)
                        .put("artifactSha256", sha256File(retained))
                        .put("manifestSha256", sha256File(manifest))
                        .put("flutterExecutable", json.optString("flutterExecutable"))
                        .put("signatureVerified", true)
                        .put("zipAligned", true)
                        .put("engineSmokeBuild", true)
                        .toString()
                )
                if (proof.exists() && !proof.delete()) throw IllegalStateException("تعذر تحديث إثبات اختبار المحرك.")
                if (!proofTemp.renameTo(proof)) throw IllegalStateException("تعذر اعتماد إثبات اختبار المحرك.")
                artifactRoot.listFiles()?.filter { it.isFile && it.name.startsWith("bisho-debug-") && it.name.endsWith(".apk") }
                    ?.sortedByDescending { it.lastModified() }?.drop(3)?.forEach { it.delete() }
                mapOf(
                    "success" to true,
                    "debugBuildSupported" to true,
                    "releaseAotSupported" to json.optBoolean("releaseAotSupported", false),
                    "artifactBytes" to retained.length(),
                    "artifactSha256" to sha256File(retained),
                    "message" to "نجح بناء Flutter Android ARM64 Debug تجريبي كامل داخل PRoot، واجتاز APK فحص التوقيع ومحاذاة ZIP. تم اعتماد المحرك للبناء المحلي Debug على هذا الجهاز. لم يتم اعتماد Release.",
                    "log" to readProbeLog(log)
                )
            }
        } catch (error: Exception) {
            mapOf("success" to false, "message" to (error.message ?: "تعذر تنفيذ اختبار البناء التجريبي."), "log" to readProbeLog(log))
        } finally {
            activeBuildProcess = null
            if (smokeRoot.exists()) smokeRoot.deleteRecursively()
            if (log.exists()) log.delete()
        }
    }

    /** Timeout polling compatible with the app's minSdk; Process.waitFor(timeout) is newer. */
    private fun waitForProcessWithTimeout(process: Process, timeout: Long, unit: TimeUnit): Boolean {
        val deadline = System.nanoTime() + unit.toNanos(timeout)
        while (true) {
            try {
                process.exitValue()
                return true
            } catch (_: IllegalThreadStateException) {
                if (System.nanoTime() >= deadline) return false
                Thread.sleep(250)
            }
        }
    }

    private fun readProbeLog(log: File): String = try {
        if (log.isFile) log.readText().takeLast(16000) else ""
    } catch (_: Exception) { "" }

    private fun inspectLocalBuildEnvironment(): Map<String, Any> {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
        val storage = StatFs(filesDir.absolutePath).availableBytes
        val missing = mutableListOf<String>()

        val engineDirectory = File(filesDir, "bisho-local-build-engine")
        val manifest = File(engineDirectory, "engine-manifest.json")
        val engineCheck = inspectToolchainManifest(engineDirectory, manifest, abi)
        val engineInstalled = engineCheck.first
        val requiredForCurrentState = if (engineInstalled) minimumBuildStorageBytes else engineInstallStorageBytes
        val deviceSupported = abi == "arm64-v8a" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && storage >= requiredForCurrentState

        if (abi != "arm64-v8a") {
            missing.add("المعمارية الحالية ($abi) غير مدعومة؛ المطلوب arm64-v8a.")
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            missing.add("يتطلب محرك البناء Android 10 أو أحدث.")
        }
        if (storage < requiredForCurrentState) {
            missing.add(if (engineInstalled)
                "المساحة الحرة أقل من 5 GB؛ يلزم توفير مساحة لملفات Gradle والبناء المؤقتة."
            else "يلزم توفير 20 GB حرة لتنزيل محرك البناء وفكّه بأمان.")
        }
        missing.addAll(engineCheck.second)

        fun verificationMatches(fileName: String, expectedMode: String): Boolean = try {
            val record = File(engineDirectory, fileName)
            if (!record.isFile || record.length() <= 0L || !manifest.isFile) false else {
                val verified = JSONObject(record.readText())
                val artifactRoot = File(filesDir, "bisho-local-build-artifacts").canonicalFile
                val artifactPath = verified.optString("artifactPath")
                val artifact = if (artifactPath.isBlank()) null else File(artifactPath).canonicalFile
                artifact != null && artifact.path.startsWith(artifactRoot.path + File.separator) &&
                    artifact.isFile && artifact.length() > 0L &&
                    verified.optString("abi") == abi && verified.optString("mode") == expectedMode &&
                    verified.optLong("apkBytes", 0L) == artifact.length() &&
                    verified.optBoolean("signatureVerified", false) &&
                    verified.optBoolean("zipAligned", false) &&
                    verified.optString("manifestSha256") == sha256File(manifest) &&
                    verified.optString("artifactSha256") == sha256File(artifact)
            }
        } catch (_: Exception) { false }
        val runtimeVerified = verificationMatches("local-build-verification.json", "release")
        val debugBuildVerified = verificationMatches("local-build-debug-verification.json", "debug")
        val canBuildLocally = deviceSupported && engineInstalled && debugBuildVerified
        val message = when {
            !deviceSupported ->
                "هذا الجهاز لا يحقق متطلبات بيئة البناء المحلية: ${missing.joinToString(" ")}"
            !engineInstalled ->
                "الجهاز يحقق متطلبات العتاد الأولية، لكن بيئة Flutter/JDK/Android SDK غير مكتملة داخل التطبيق. ${missing.joinToString(" ")}"
            !debugBuildVerified ->
                "ملفات المحرك موجودة؛ يلزم تنفيذ Debug APK فعلي والتحقق من توقيعه ومحاذاته على هذا الجهاز."
            !runtimeVerified ->
                "بناء Debug المحلي اجتاز الاختبار. لم ينجح بعد بناء Release/AOT؛ لا تعتبر نسخة الإنتاج جاهزة."
            else -> "اجتاز المحرك اختباري Debug وRelease وإثبات APK على هذا الجهاز."
        }

        return mapOf(
            "deviceAbi" to abi,
            "androidVersion" to Build.VERSION.SDK_INT,
            "availableBytes" to storage,
            "requiredStorageBytes" to requiredForCurrentState,
            "engineInstallStorageBytes" to engineInstallStorageBytes,
            "deviceSupported" to deviceSupported,
            "engineInstalled" to engineInstalled,
            "runtimeVerified" to runtimeVerified,
            "debugBuildVerified" to debugBuildVerified,
            "canBuildLocally" to canBuildLocally,
            "missingRequirements" to missing,
            "message" to message
        )
    }

    /**
     * Validate the layout of a future toolchain bundle. This does not
     * claim that Linux executables can run on Android; runtime execution and a
     * successful local APK build still require a separate device-side probe.
     */
    private fun inspectToolchainManifest(
        engineDirectory: File,
        manifest: File,
        deviceAbi: String
    ): Pair<Boolean, List<String>> {
        val missing = mutableListOf<String>()
        if (!manifest.isFile || manifest.length() == 0L || manifest.length() > 1024L * 1024L) {
            missing.add("لم يتم تثبيت بيان محرك بناء صالح أو تجاوز حجمه الحد الآمن.")
            return Pair(false, missing)
        }

        return try {
            val json = JSONObject(manifest.readText())
            if (json.optInt("schemaVersion", -1) != 1) {
                missing.add("إصدار بيان محرك البناء غير مدعوم.")
            }
            if (json.optString("abi") != deviceAbi) {
                missing.add("حزمة محرك البناء لا تطابق معمارية الهاتف.")
            }
            if (!json.optBoolean("debugBuildSupported", false)) {
                missing.add("الحزمة لم تجتز اختبار بناء Flutter Debug حقيقي عند تجهيزها؛ أعد تجهيزها باستخدام validate_and_pack.sh.")
            }
            if (json.has("releaseAotSupported") && json.opt("releaseAotSupported") !is Boolean) {
                missing.add("حقل releaseAotSupported في بيان المحرك يجب أن يكون true أو false.")
            }

            val launcher = resolveInside(engineDirectory, json.optString("runtimeLauncher"))
            val rootfs = resolveInside(engineDirectory, json.optString("rootfsDirectory"))
            val flutter = resolveInside(engineDirectory, json.optString("flutterExecutable"))
            val java = resolveInside(engineDirectory, json.optString("javaExecutable"))
            val sdk = resolveInside(engineDirectory, json.optString("androidSdkDirectory"))

            if (rootfs != null && rootfs.isDirectory) {
                val prefix = rootfs.canonicalPath + File.separator
                for ((label, candidate) in listOf("Flutter" to flutter, "Java" to java, "Android SDK" to sdk)) {
                    if (candidate != null && !candidate.canonicalPath.startsWith(prefix)) {
                        missing.add("مسار $label يجب أن يكون داخل نظام Linux الجذري.")
                    }
                }
            }

            if (launcher == null || !launcher.isFile || !launcher.canExecute()) {
                missing.add("مشغل بيئة Linux المدمجة غير موجود أو غير قابل للتنفيذ.")
            }
            if (rootfs == null || !rootfs.isDirectory) {
                missing.add("نظام ملفات Linux الجذري غير مثبت.")
            } else if (!File(rootfs, "bin/sh").isFile || !File(rootfs, "bin/sh").canExecute()) {
                missing.add("نظام Linux الجذري لا يحتوي /bin/sh قابلًا للتنفيذ.")
            }
            if (flutter == null || !flutter.isFile || !flutter.canExecute()) {
                missing.add("ملف Flutter التنفيذي غير موجود أو لا يملك صلاحية التنفيذ.")
            }
            if (java == null || !java.isFile || !java.canExecute()) {
                missing.add("ملف Java التنفيذي غير موجود أو لا يملك صلاحية التنفيذ.")
            }
            if (sdk == null || !sdk.isDirectory) {
                missing.add("مجلد Android SDK غير موجود.")
            } else {
                for (component in listOf("platforms", "build-tools", "platform-tools", "licenses", "cmdline-tools/latest/bin")) {
                    if (!File(sdk, component).isDirectory) missing.add("Android SDK يفتقد مجلد $component.")
                }
                val hasAndroidLicense = File(sdk, "licenses/android-sdk-license").let { it.isFile && it.length() > 0L }
                if (!hasAndroidLicense) missing.add("ملف موافقة Android SDK license غير موجود؛ أكمِل قبول التراخيص ضمن حزمة المحرك.")
                val hasPlatformJar = File(sdk, "platforms").listFiles()?.any { platform ->
                    platform.isDirectory && File(platform, "android.jar").isFile
                } == true
                if (!hasPlatformJar) missing.add("Android SDK لا يحتوي منصة Android مكتملة بملف android.jar.")
                if (!File(sdk, "cmdline-tools/latest/bin/sdkmanager").isFile ||
                    !File(sdk, "cmdline-tools/latest/bin/sdkmanager").canExecute()) {
                    missing.add("Android SDK يفتقد أداة sdkmanager القابلة للتنفيذ.")
                }
                val hasBuildTools = File(sdk, "build-tools").listFiles()?.any { version ->
                    version.isDirectory && listOf("aapt2", "aidl", "zipalign", "split-select", "apksigner").all { tool ->
                        val file = File(version, tool)
                        file.isFile && file.canExecute()
                    }
                } == true
                if (!hasBuildTools) missing.add("لا توجد أدوات Build Tools كاملة قابلة للتنفيذ (aapt2/aidl/zipalign/apksigner).")
            }

            val valid = missing.isEmpty()
            Pair(valid, missing)
        } catch (_: Exception) {
            missing.add("تعذر قراءة بيان محرك البناء أو أن تنسيقه غير صالح.")
            Pair(false, missing)
        }
    }

    private fun sha256File(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun resolveInside(root: File, relativePath: String): File? {
        if (relativePath.isBlank() || relativePath.startsWith('/') || relativePath.contains('\\')) return null
        if (relativePath.split('/').any { it.isBlank() || it == "." || it == ".." }) return null
        return try {
            val canonicalRoot = root.canonicalFile
            val candidate = File(canonicalRoot, relativePath).canonicalFile
            val prefix = canonicalRoot.path + File.separator
            if (candidate.path.startsWith(prefix)) candidate else null
        } catch (_: Exception) {
            null
        }
    }
}
