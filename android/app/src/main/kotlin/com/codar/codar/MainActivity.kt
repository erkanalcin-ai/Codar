package com.codar.codar

import android.content.ContentUris
import android.content.ContentValues
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.view.View
import android.view.WindowInsetsController
import java.io.File
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Codar's book-file channel. API 29+ uses scoped MediaStore Downloads with
 * `RELATIVE_PATH`; API 24-28 use an app-specific external directory because
 * public MediaStore writes there require broad storage permission.
 *
 * No MANAGE_EXTERNAL_STORAGE or legacy storage permission is needed. Only the
 * app's own entries are listed/read.
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
                        "movePickedFile" -> {
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime") ?: "application/octet-stream"
                            val sourceUri = call.argument<String>("sourceUri")!!
                            val size = call.argument<Number>("size")?.toLong() ?: -1L
                            result.success(movePickedFile(name, mime, sourceUri, size))
                        }
                        "readFile" -> {
                            val uri = call.argument<String>("uri")!!
                            result.success(readFile(uri))
                        }
                        "listCodarLib" -> result.success(listCodarLib())
                        "setSystemUi" -> {
                            val lightStatusBar =
                                call.argument<Boolean>("lightStatusBar") ?: false
                            setSystemUi(lightStatusBar)
                            result.success(null)
                        }
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
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            importModernMediaStore(name, mime, bytes)
        } else {
            importLegacyAppStorage(name, bytes)
        }
    }

    /**
     * Android 15+ enforces edge-to-edge and can ignore Flutter's overlay
     * brightness request. Keep the status-bar icon mode aligned with the
     * active Codar surface without changing the storage architecture.
     */
    private fun setSystemUi(lightStatusBar: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val layoutFlags =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        val brightnessFlag =
            if (lightStatusBar) View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR else 0
        window.decorView.systemUiVisibility = layoutFlags or brightnessFlag
        window.statusBarColor = if (lightStatusBar) {
            Color.rgb(246, 240, 226)
        } else {
            Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val appearance =
                if (lightStatusBar) WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS else 0
            window.insetsController?.setSystemBarsAppearance(
                appearance,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
            )
        }
    }

    /**
     * Streams the original picker URI into CodarLib and removes the source
     * only after a complete, size-checked write. A failed validation never
     * calls this method, so corrupt books remain in their original folder.
     */
    private fun movePickedFile(
        name: String,
        mime: String,
        sourceUriString: String,
        expectedSize: Long
    ): String {
        val sourceUri = Uri.parse(sourceUriString)
        if (sourceUri.scheme.isNullOrEmpty()) {
            throw IllegalArgumentException("Invalid source URI: $sourceUriString")
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            moveModernMediaStore(name, mime, sourceUri, expectedSize)
        } else {
            moveLegacyAppStorage(name, sourceUri, expectedSize)
        }
    }

    private fun moveModernMediaStore(
        name: String,
        mime: String,
        sourceUri: Uri,
        expectedSize: Long
    ): String {
        val safeName = safeFileName(name)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, downloadsRelativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val destination = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert returned null")
        try {
            val output = contentResolver.openOutputStream(destination)
                ?: throw IllegalStateException("Cannot open CodarLib output stream")
            output.use { copySource(sourceUri, it, expectedSize) }
            val published = contentResolver.update(destination, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            if (published != 1) {
                throw IllegalStateException("Cannot publish CodarLib entry")
            }
            if (!deleteSource(sourceUri)) {
                throw IllegalStateException("Selected source could not be removed")
            }
            return destination.toString()
        } catch (t: Throwable) {
            contentResolver.delete(destination, null, null)
            throw t
        }
    }

    private fun moveLegacyAppStorage(
        name: String,
        sourceUri: Uri,
        expectedSize: Long
    ): String {
        val directory = legacyLibraryDir()
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Cannot create legacy CodarLib directory")
        }
        val destination = uniqueLegacyFile(directory, safeFileName(name))
        try {
            FileOutputStream(destination).use { output ->
                copySource(sourceUri, output, expectedSize)
            }
            if (!deleteSource(sourceUri)) {
                throw IllegalStateException("Selected source could not be removed")
            }
            return Uri.fromFile(destination).toString()
        } catch (t: Throwable) {
            destination.delete()
            throw t
        }
    }

    private fun copySource(sourceUri: Uri, output: OutputStream, expectedSize: Long) {
        val input = openSourceInput(sourceUri)
            ?: throw IllegalStateException("Cannot open selected source: $sourceUri")
        var total = 0L
        input.use { rawInput ->
            BufferedInputStream(rawInput).use { bufferedInput ->
                BufferedOutputStream(output).use { bufferedOutput ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = bufferedInput.read(buffer)
                        if (read < 0) break
                        bufferedOutput.write(buffer, 0, read)
                        total += read
                    }
                    bufferedOutput.flush()
                }
            }
        }
        if (expectedSize >= 0 && total != expectedSize) {
            throw IllegalStateException(
                "Selected source changed while importing: expected $expectedSize bytes, got $total"
            )
        }
    }

    private fun openSourceInput(sourceUri: Uri): InputStream? {
        return if (sourceUri.scheme == "file") {
            val path = sourceUri.path ?: throw IllegalArgumentException("Invalid file URI")
            FileInputStream(File(path))
        } else {
            contentResolver.openInputStream(sourceUri)
        }
    }

    private fun deleteSource(sourceUri: Uri): Boolean {
        if (sourceUri.scheme == "file") {
            val path = sourceUri.path ?: return false
            return File(path).delete()
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT &&
            DocumentsContract.isDocumentUri(this, sourceUri)
        ) {
            DocumentsContract.deleteDocument(contentResolver, sourceUri)
        } else {
            contentResolver.delete(sourceUri, null, null) > 0
        }
    }

    private fun importModernMediaStore(name: String, mime: String, bytes: ByteArray): String {
        val safeName = safeFileName(name)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, downloadsRelativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert returned null")
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Cannot open output stream for $uri")
            val published = contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            if (published != 1) {
                throw IllegalStateException("Cannot publish CodarLib entry")
            }
            return uri.toString()
        } catch (t: Throwable) {
            contentResolver.delete(uri, null, null)
            throw t
        }
    }

    private fun importLegacyAppStorage(name: String, bytes: ByteArray): String {
        val directory = legacyLibraryDir()
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Cannot create legacy CodarLib directory")
        }
        val file = uniqueLegacyFile(directory, safeFileName(name))
        file.writeBytes(bytes)
        return Uri.fromFile(file).toString()
    }

    private fun readFile(uriString: String): ByteArray {
        val uri = Uri.parse(uriString)
        if (uri.scheme == "file") {
            val path = uri.path ?: throw IllegalStateException("Invalid file URI: $uriString")
            return File(path).readBytes()
        }
        return contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Cannot open input stream for $uriString")
    }

    private fun listCodarLib(): List<Map<String, String>> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            listModernMediaStore()
        } else {
            legacyLibraryDir().listFiles()
                .orEmpty()
                .filter { it.isFile }
                .map { mapOf("name" to it.name, "uri" to Uri.fromFile(it).toString()) }
        }
    }

    private fun listModernMediaStore(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME
        )
        // Only our own entries: no permission needed, no other app's files leak in.
        val selection = "${MediaStore.MediaColumns.OWNER_PACKAGE_NAME} = ? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val args = arrayOf(applicationContext.packageName, downloadsRelativePath)
        contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                out.add(mapOf("name" to cursor.getString(nameCol), "uri" to uri))
            }
        }
        return out
    }

    private fun deleteMediaFile(uriString: String): Boolean {
        val uri = Uri.parse(uriString)
        if (uri.scheme == "file") {
            val path = uri.path ?: return false
            return File(path).delete()
        }
        return contentResolver.delete(uri, null, null) > 0
    }

    private val downloadsRelativePath =
        Environment.DIRECTORY_DOWNLOADS + "/CodarLib/"

    private fun legacyLibraryDir(): File {
        val root = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        return File(root, "CodarLib")
    }

    private fun safeFileName(name: String): String {
        val candidate = name.substringAfterLast('/').substringAfterLast('\\')
            .trim().take(128)
        if (candidate.isEmpty() || candidate == "." || candidate == "..") return "book"
        return candidate
    }

    private fun uniqueLegacyFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "$stem ($index)$extension")
            index++
        }
        return candidate
    }
}
