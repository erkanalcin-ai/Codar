package com.codar.codar

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phase 1 spike channel: proves Codar can own `Downloads/CodarLib/` through
 * MediaStore on modern Android (scoped storage, API 29+).
 *
 * No MANAGE_EXTERNAL_STORAGE. Only the app's own entries are listed/read,
 * which requires no storage permission.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "codar/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "importFile" -> {
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime") ?: "application/octet-stream"
                            val bytes = call.argument<ByteArray>("bytes")!!
                            result.success(importFile(name, mime, bytes))
                        }
                        "readFile" -> {
                            val uri = call.argument<String>("uri")!!
                            result.success(readFile(uri))
                        }
                        "listCodarLib" -> result.success(listCodarLib())
                        "deleteFile" -> {
                            val uri = call.argument<String>("uri")!!
                            result.success(deleteMediaFile(uri))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("STORAGE_ERROR", e.message, null)
                }
            }
    }

    private fun importFile(name: String, mime: String, bytes: ByteArray): String {
        val safeName = name.substringAfterLast('/').take(128)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, safeName)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/CodarLib/")
            }
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert returned null")
        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("Cannot open output stream for $uri")
        return uri.toString()
    }

    private fun readFile(uriString: String): ByteArray {
        val uri = android.net.Uri.parse(uriString)
        return contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Cannot open input stream for $uriString")
    }

    private fun listCodarLib(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.Downloads._ID,
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.RELATIVE_PATH,
            MediaStore.Downloads.SIZE
        )
        // Only our own entries: no permission needed, no other app's files leak in.
        val selection: String?
        val args: Array<String>?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection = "${MediaStore.Downloads.OWNER_PACKAGE_NAME} = ?"
            args = arrayOf(applicationContext.packageName)
        } else {
            selection = "${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
            args = arrayOf("%CodarLib%")
        }
        contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                out.add(mapOf("name" to cursor.getString(nameCol), "uri" to uri))
            }
        }
        return out
    }

    private fun deleteMediaFile(uriString: String): Boolean {
        val uri = android.net.Uri.parse(uriString)
        return contentResolver.delete(uri, null, null) > 0
    }
}
