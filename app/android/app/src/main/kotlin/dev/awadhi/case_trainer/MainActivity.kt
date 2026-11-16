package dev.awadhi.case_trainer

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves finished-case reports into the public Downloads/CaseTrainer folder (owner request 2026-11-16), through
 * MediaStore on Android 10+ so no storage permission is needed.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "case_trainer/files").setMethodCallHandler { call, result ->
            if (call.method != "saveToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val name = call.argument<String>("name")!!
                val bytes = call.argument<ByteArray>("bytes")!!
                val mime = call.argument<String>("mime") ?: "application/pdf"
                result.success(save(name, bytes, mime))
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
        }
    }

    private fun save(name: String, bytes: ByteArray, mime: String): String {
        val folder = "CaseTrainer"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$folder")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore refused the file")
            resolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            // Android 8/9: the app-specific Downloads folder (no permission needed).
            val dir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), folder).apply { mkdirs() }
            File(dir, name).writeBytes(bytes)
        }
        return "Downloads/$folder/$name"
    }
}
