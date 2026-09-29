package com.codar.codar

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowInsetsController
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
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
    private var openWithChannel: MethodChannel? = null
    private val pendingOpenWithFiles = mutableListOf<Map<String, Any>>()
    private val storageExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        enqueueOpenWithFile(intent, notifyFlutter = false)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueOpenWithFile(intent, notifyFlutter = true)
    }

    override fun onDestroy() {
        // Let submitted storage work finish; shutdownNow could interrupt a file copy.
        storageExecutor.shutdown()
        super.onDestroy()
    }

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
                        "copyPickedFile" -> {
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime") ?: "application/octet-stream"
                            val sourceUri = call.argument<String>("sourceUri")!!
                            val size = call.argument<Number>("size")?.toLong() ?: -1L
                            runStorageTask(result) {
                                copyPickedFile(name, mime, sourceUri, size)
                            }
                        }
                        "deletePickedSource" -> {
                            val sourceUri = Uri.parse(call.argument<String>("sourceUri")!!)
                            result.success(deleteSource(sourceUri))
                        }
                        "readFile" -> {
                            val uri = call.argument<String>("uri")!!
                            val maxBytes = call.argument<Number>("maxBytes")?.toLong()
                                ?: throw IllegalArgumentException("Missing readFile size limit")
                            result.success(readFile(uri, maxBytes))
                        }
                        "copyFileToPath" -> {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            val path = call.argument<String>("path")!!
                            val size = call.argument<Number>("size")?.toLong() ?: -1L
                            runStorageTask(result) { copyFileToPath(uri, path, size) }
                        }
                        "copyExternalToPath" -> {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            val path = call.argument<String>("path")!!
                            val maxBytes = call.argument<Number>("maxBytes")?.toLong()
                                ?: throw IllegalArgumentException("Missing external file size limit")
                            runStorageTask(result) {
                                copyExternalToPath(uri, path, maxBytes)
                            }
                        }
                        "listTreeFiles" -> {
                            val treeUri = call.argument<String>("treeUri")!!
                            result.success(listTreeFiles(treeUri))
                        }
                        "isCodarLibRoot" -> {
                            val location = call.argument<String>("location")!!
                            result.success(isCodarLibRoot(location))
                        }
                        "managedFileState" -> {
                            val uri = call.argument<String>("uri")!!
                            runStorageTask(result) { managedFileState(uri) }
                        }
                        "listCodarLib" -> result.success(listCodarLib())
                        "setSystemUi" -> {
                            val lightStatusBar =
                                call.argument<Boolean>("lightStatusBar") ?: false
                            setSystemUi(lightStatusBar)
                            result.success(null)
                        }
                        "setReaderBrightness" -> {
                            val brightness = call.argument<Number>("brightness")?.toFloat() ?: -1f
                            setReaderBrightness(brightness)
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
        openWithChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "codar/open_with",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takePendingOpenWithFiles") {
                    val pending = pendingOpenWithFiles.toList()
                    pendingOpenWithFiles.clear()
                    result.success(pending)
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codar/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(
                        mapOf(
                            "name" to (packageManager.getPackageInfo(packageName, 0)
                                .versionName ?: ""),
                            "code" to installedVersionCode().toString(),
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun <T> runStorageTask(result: MethodChannel.Result, task: () -> T) {
        storageExecutor.execute {
            try {
                val value = task()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("STORAGE_ERROR", error.message, null)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun installedVersionCode(): Long {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
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

    private fun setReaderBrightness(value: Float) {
        val attributes = window.attributes
        attributes.screenBrightness = if (value < 0f) -1f else value.coerceIn(0.05f, 1f)
        window.attributes = attributes
    }

    private fun enqueueOpenWithFile(intent: Intent?, notifyFlutter: Boolean) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val fileInfo = mapOf(
            "uri" to uri.toString(),
            "displayName" to queryDisplayName(uri),
            "mimeType" to (intent.type ?: contentResolver.getType(uri) ?: ""),
            "size" to querySize(uri),
        )
        val channel = if (notifyFlutter) openWithChannel else null
        if (channel == null) {
            pendingOpenWithFiles.add(fileInfo)
        } else {
            channel.invokeMethod("openWithFile", fileInfo)
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        if (uri.scheme == "file") return File(uri.path ?: "").name
        var name = ""
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0) name = cursor.getString(column) ?: ""
            }
        }
        return name.ifBlank { uri.lastPathSegment ?: "Imported book" }
    }

    private fun querySize(uri: Uri): Long {
        if (uri.scheme == "file") return File(uri.path ?: "").length()
        var size = -1L
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val column = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (column >= 0 && !cursor.isNull(column)) size = cursor.getLong(column)
            }
        }
        return size
    }

    /**
     * Streams the selected URI into CodarLib without removing the source.
     * Dart deletes the source only after the database commit succeeds.
     */
    private fun copyPickedFile(
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
            copyModernMediaStore(name, mime, sourceUri, expectedSize)
        } else {
            copyLegacyAppStorage(name, sourceUri, expectedSize)
        }
    }

    private fun copyModernMediaStore(
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
            return destination.toString()
        } catch (t: Throwable) {
            contentResolver.delete(destination, null, null)
            throw t
        }
    }

    private fun copyLegacyAppStorage(
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
            return Uri.fromFile(destination).toString()
        } catch (t: Throwable) {
            destination.delete()
            throw t
        }
    }

    private fun copySource(
        sourceUri: Uri,
        output: OutputStream,
        expectedSize: Long,
        maxBytes: Long = Long.MAX_VALUE,
    ) {
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
                        if (total + read > maxBytes) {
                            throw IllegalArgumentException("Selected file exceeds import size limit")
                        }
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

    private fun readFile(uriString: String, maxBytes: Long): ByteArray {
        require(maxBytes > 0) { "Invalid readFile size limit" }
        val uri = Uri.parse(uriString)
        val input = openSourceInput(uri)
            ?: throw IllegalStateException("Cannot open input stream for $uriString")
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        input.use { stream ->
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                if (read == 0) continue
                if (total + read > maxBytes) {
                    throw IllegalArgumentException("Selected file exceeds import size limit")
                }
                output.write(buffer, 0, read)
                total += read
            }
        }
        return output.toByteArray()
    }

    private fun copyFileToPath(uri: Uri, path: String, expectedSize: Long): Boolean {
        val destination = File(path)
        destination.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) {
                throw IllegalStateException("Cannot create staging directory")
            }
        }
        try {
            FileOutputStream(destination).use { output ->
                copySource(uri, output, expectedSize)
            }
            return true
        } catch (t: Throwable) {
            destination.delete()
            throw t
        }
    }

    private fun copyExternalToPath(uri: Uri, path: String, maxBytes: Long): Boolean {
        require(maxBytes > 0) { "Invalid external file size limit" }
        val destination = File(path)
        destination.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) {
                throw IllegalStateException("Cannot create staging directory")
            }
        }
        try {
            FileOutputStream(destination).use { output ->
                copySource(uri, output, -1L, maxBytes)
            }
            return true
        } catch (t: Throwable) {
            destination.delete()
            throw t
        }
    }

    /**
     * Enumerates a user-granted SAF tree without converting it to a raw path.
     * The returned child URIs are read-only import sources; Flutter copies
     * their bytes into CodarLib and never deletes the selected originals.
     */
    private fun listTreeFiles(treeUriString: String): List<Map<String, Any>> {
        val treeUri = Uri.parse(treeUriString)
        if (treeUri.scheme != "content") {
            throw IllegalArgumentException("Invalid SAF tree URI: $treeUriString")
        }
        val out = mutableListOf<Map<String, Any>>()
        enumerateTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
            mutableSetOf(),
            out,
        )
        return out
    }

    /**
     * Matches the complete SAF tree identity against the app's actual storage
     * destination. A matching last path segment or display name is insufficient.
     */
    private fun isCodarLibRoot(location: String): Boolean {
        val uri = Uri.parse(location)
        if (uri.scheme == "content") {
            if (uri.authority != "com.android.externalstorage.documents") return false
            val selectedDocumentId = try {
                DocumentsContract.getTreeDocumentId(uri).trimEnd('/')
            } catch (_: IllegalArgumentException) {
                return false
            }
            return selectedDocumentId == codarLibTreeDocumentId()
        }

        val selectedPath = when (uri.scheme) {
            "file" -> uri.path ?: return false
            null, "" -> location
            else -> return false
        }
        return try {
            File(selectedPath).canonicalPath == codarLibRootDirectory().canonicalPath
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Tri-state-safe URI check used by library reconciliation. A failed or
     * denied provider query is unknown, never proof that a user's book died.
     */
    private fun managedFileState(uriString: String): String {
        return try {
            val uri = Uri.parse(uriString)
            if (uri.scheme == "file") {
                val path = uri.path ?: return "unknown"
                val root = codarLibRootDirectory().canonicalPath.trimEnd(File.separatorChar)
                val canonical = File(path).canonicalPath
                if (!canonical.startsWith(root + File.separator)) return "external"
                return if (File(canonical).isFile) "managed_present" else "managed_missing"
            }
            if (uri.scheme != "content") return "external"

            if (uri.authority == "com.android.externalstorage.documents") {
                // A SAF tree URI is a provider grant, not CodarLib identity.
                // Resolve only the exact path to an app-owned MediaStore row;
                // a display-name match alone must never establish ownership.
                return if (managedMediaStoreUriFromTreeDocument(uri) != null) {
                    "managed_present"
                } else {
                    "external"
                }
            }

            // Modern CodarLib files are created in this exact MediaStore
            // Downloads collection. A live row is trusted only when both its
            // owner and relative path match this app's managed destination.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                isCodarDownloadsRowUri(uri)
            ) {
                val cursor = contentResolver.query(
                    uri,
                    arrayOf(
                        MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
                        MediaStore.MediaColumns.RELATIVE_PATH,
                    ),
                    null,
                    null,
                    null,
                ) ?: return "unknown"
                return cursor.use {
                    if (!it.moveToFirst()) return@use "managed_missing"
                    val ownerColumn = it.getColumnIndex(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
                    val pathColumn = it.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    if (ownerColumn < 0 || pathColumn < 0) return@use "unknown"
                    if (it.getString(ownerColumn) == applicationContext.packageName &&
                        it.getString(pathColumn) == downloadsRelativePath
                    ) "managed_present" else "external"
                }
            }
            "external"
        } catch (_: SecurityException) {
            "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }

    @Suppress("DEPRECATION")
    private fun codarLibTreeDocumentId(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return "primary:${downloadsRelativePath.trimEnd('/')}"
        }
        val externalRoot = try {
            Environment.getExternalStorageDirectory().canonicalPath
        } catch (_: Exception) {
            return null
        }
        val libraryPath = try {
            legacyLibraryDir().canonicalPath
        } catch (_: Exception) {
            return null
        }
        val prefix = externalRoot.trimEnd(File.separatorChar) + File.separator
        if (!libraryPath.startsWith(prefix)) return null
        val relativePath = libraryPath.substring(prefix.length)
            .replace(File.separatorChar, '/')
        if (relativePath.isEmpty() || relativePath == ".." || relativePath.startsWith("../")) {
            return null
        }
        return "primary:$relativePath"
    }

    @Suppress("DEPRECATION")
    private fun codarLibRootDirectory(): File =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            File(Environment.getExternalStorageDirectory(), downloadsRelativePath.trimEnd('/'))
        } else {
            legacyLibraryDir()
        }

    private fun enumerateTree(
        treeUri: Uri,
        parentId: String,
        visited: MutableSet<String>,
        out: MutableList<Map<String, Any>>
    ) {
        if (!visited.add(parentId)) return

        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        val cursor = contentResolver.query(childrenUri, projection, null, null, null)
            ?: throw IllegalStateException("Cannot enumerate SAF tree")
        cursor.use {
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val sizeColumn = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_SIZE,
            )
            while (cursor.moveToNext()) {
                val childId = cursor.getString(idColumn)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    childId,
                )
                val mime = cursor.getString(mimeColumn) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    enumerateTree(treeUri, childId, visited, out)
                    continue
                }
                val name = cursor.getString(nameColumn) ?: ""
                val size = if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                    cursor.getLong(sizeColumn)
                } else {
                    -1L
                }
                out.add(
                    mapOf(
                        "name" to name,
                        "uri" to childUri.toString(),
                        "size" to size,
                    ),
                )
            }
        }
    }

    private fun listCodarLib(): List<Map<String, Any>> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            listModernMediaStore()
        } else {
            (legacyLibraryDir().listFiles()
                ?: throw IllegalStateException("Cannot list CodarLib files"))
                .filter { it.isFile }
                .map {
                    mapOf(
                        "name" to it.name,
                        "uri" to Uri.fromFile(it).toString(),
                        "size" to it.length(),
                    )
                }
        }
    }

    private fun listModernMediaStore(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
        )
        // Only our own entries: no permission needed, no other app's files leak in.
        val selection = "${MediaStore.MediaColumns.OWNER_PACKAGE_NAME} = ? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val args = arrayOf(applicationContext.packageName, downloadsRelativePath)
        val cursor = contentResolver.query(collection, projection, selection, args, null)
            ?: throw IllegalStateException("Cannot query CodarLib files")
        cursor.use {
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                out.add(
                    mapOf(
                        "name" to cursor.getString(nameCol),
                        "uri" to uri,
                        "size" to cursor.getLong(sizeCol),
                    ),
                )
            }
        }
        return out
    }

    private fun deleteMediaFile(uriString: String): Boolean {
        val uri = Uri.parse(uriString)
        if (uri.scheme == "file") {
            val path = uri.path ?: return false
            if (managedFileState(uriString) != "managed_present") return false
            return File(path).delete()
        }
        // Never delete arbitrary content URIs from book_files. Resolve to a
        // live MediaStore row whose owner and complete CodarLib path match.
        val managedUri = managedMediaStoreUri(uri) ?: return false
        return contentResolver.delete(managedUri, null, null) > 0
    }

    /** Matches only a row URI from the exact MediaStore collection Codar writes. */
    private fun isCodarDownloadsRowUri(uri: Uri): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            uri.scheme != "content" ||
            uri.authority != MediaStore.AUTHORITY
        ) {
            return false
        }
        val rowSegments = uri.pathSegments
        val collections = listOf(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
            MediaStore.VOLUME_EXTERNAL,
        )
        return collections.any { volume ->
            val collectionSegments = MediaStore.Downloads.getContentUri(
                volume,
            ).pathSegments
            rowSegments.size == collectionSegments.size + 1 &&
                rowSegments.take(collectionSegments.size) == collectionSegments &&
                rowSegments.lastOrNull()?.toLongOrNull() != null
        }
    }

    private fun managedMediaStoreUri(uri: Uri): Uri? {
        if (isCodarDownloadsRowUri(uri)) {
            return uri.takeIf { managedFileState(it.toString()) == "managed_present" }
        }
        if (uri.authority == "com.android.externalstorage.documents") {
            return managedMediaStoreUriFromTreeDocument(uri)
        }
        return null
    }

    private fun managedMediaStoreUriFromTreeDocument(uri: Uri): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val rootId = codarLibTreeDocumentId()?.trimEnd('/') ?: return null
        val documentId = try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: IllegalArgumentException) {
            return null
        }
        if (!documentId.startsWith("$rootId/")) return null

        val relative = documentId.removePrefix("primary:")
        val prefix = downloadsRelativePath
        if (!relative.startsWith(prefix)) return null
        val entryName = relative.removePrefix(prefix)
        // CodarLib's managed MediaStore contract stores files directly in its
        // root. Nested or ambiguous paths are not silently mapped.
        if (entryName.isEmpty() || entryName.contains('/')) return null

        val collection = MediaStore.Downloads.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val cursor = contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.OWNER_PACKAGE_NAME} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ?",
            arrayOf(applicationContext.packageName, downloadsRelativePath, entryName),
            null,
        ) ?: return null
        return cursor.use {
            val idColumn = it.getColumnIndex(MediaStore.MediaColumns._ID)
            if (idColumn < 0 || !it.moveToFirst()) return@use null
            val id = it.getLong(idColumn)
            if (it.moveToNext()) return@use null
            ContentUris.withAppendedId(collection, id)
        }
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
