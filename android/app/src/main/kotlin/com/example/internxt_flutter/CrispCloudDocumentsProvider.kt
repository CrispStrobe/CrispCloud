// android/app/src/main/kotlin/com/example/internxt_flutter/CrispCloudDocumentsProvider.kt
//
// CrispCloudDocumentsProvider — Android DocumentsProvider implementation.
//
// Makes CrispCloud appear as a storage location in Android's system file
// picker (Documents UI), so any app that uses ACTION_OPEN_DOCUMENT or
// ACTION_CREATE_DOCUMENT can access cloud files stored in CrispCloud.
//
// Architecture:
//   - Runs in the main app process (same UID).
//   - Reads connected-provider metadata from SharedPreferences (written by
//     the Flutter side via DocumentsProviderBridge).
//   - Delegates file operations to the Flutter engine via a MethodChannel
//     (channel name: com.crispcloud/documents_provider).
//   - Document IDs use the format "<provider>:<path>", e.g. "s3:/bucket/file.txt".
//
// Supported capabilities:
//   FLAG_SUPPORTS_CREATE, FLAG_SUPPORTS_DELETE, FLAG_SUPPORTS_RENAME,
//   FLAG_DIR_SUPPORTS_CREATE.

package com.example.internxt_flutter

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.database.MatrixCursor
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import android.util.Log
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Metadata for a single connected cloud provider, deserialized from the
 * SharedPreferences JSON array written by DocumentsProviderBridge on the
 * Dart side.
 */
data class ProviderEntry(
    val provider: String,
    val label: String,
    val rootDocumentId: String = "$provider:/"
)

/**
 * DocumentsProvider that surfaces CrispCloud storage in the Android
 * system file picker and any app using the Storage Access Framework.
 */
class CrispCloudDocumentsProvider : DocumentsProvider() {

    companion object {
        private const val TAG = "CrispCloudDP"

        /** SharedPreferences file name (must match DocumentsProviderBridge). */
        const val PREFS_NAME = "crisp_cloud_documents_provider"

        /** Key under which connected providers are stored as a JSON array. */
        const val PREFS_KEY_PROVIDERS = "connected_providers"

        /** MethodChannel name (must match DocumentsProviderBridge). */
        const val CHANNEL_NAME = "com.crispcloud/documents_provider"

        // Default columns for root queries.
        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_SUMMARY,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_MIME_TYPES,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_AVAILABLE_BYTES
        )

        // Default columns for document queries.
        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE
        )

        /** Timeout for synchronous MethodChannel calls (milliseconds). */
        private const val CHANNEL_TIMEOUT_MS = 15_000L

        /** Build a document ID from provider name and remote path. */
        fun makeDocumentId(provider: String, path: String): String =
            "$provider:$path"

        /** Parse a document ID into (provider, path). Returns null if malformed. */
        fun parseDocumentId(documentId: String): Pair<String, String>? {
            val colonIdx = documentId.indexOf(':')
            if (colonIdx < 1) return null
            val provider = documentId.substring(0, colonIdx)
            val path = documentId.substring(colonIdx + 1).ifEmpty { "/" }
            return Pair(provider, path)
        }

        /** Infer MIME type from a file name. Returns directory MIME for folders. */
        fun mimeTypeFor(name: String, isDirectory: Boolean): String {
            if (isDirectory) return DocumentsContract.Document.MIME_TYPE_DIR
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext.isEmpty()) return "application/octet-stream"
            return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                ?: "application/octet-stream"
        }
    }

    // -------------------------------------------------------------------------
    // Initialisation
    // -------------------------------------------------------------------------

    override fun onCreate(): Boolean {
        Log.d(TAG, "CrispCloudDocumentsProvider created")
        return true
    }

    // -------------------------------------------------------------------------
    // Root query
    // -------------------------------------------------------------------------

    /**
     * Returns one row per connected cloud provider.
     * Each row represents a storage "root" in the file picker sidebar.
     */
    override fun queryRoots(projection: Array<String>?): Cursor {
        val cols = projection ?: DEFAULT_ROOT_PROJECTION
        val cursor = MatrixCursor(cols)

        val providers = readConnectedProviders()
        if (providers.isEmpty()) {
            // Return empty cursor — picker shows no CrispCloud entry.
            return cursor
        }

        for (entry in providers) {
            val flags = DocumentsContract.Root.FLAG_SUPPORTS_CREATE or
                    DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD or
                    DocumentsContract.Root.FLAG_LOCAL_ONLY

            val row = cursor.newRow()
            for (col in cols) {
                when (col) {
                    DocumentsContract.Root.COLUMN_ROOT_ID ->
                        row.add(entry.provider)
                    DocumentsContract.Root.COLUMN_DOCUMENT_ID ->
                        row.add(entry.rootDocumentId)
                    DocumentsContract.Root.COLUMN_TITLE ->
                        row.add(entry.label.ifEmpty { entry.provider })
                    DocumentsContract.Root.COLUMN_SUMMARY ->
                        row.add("CrispCloud – ${entry.provider}")
                    DocumentsContract.Root.COLUMN_FLAGS ->
                        row.add(flags)
                    DocumentsContract.Root.COLUMN_MIME_TYPES ->
                        row.add("*/*")
                    DocumentsContract.Root.COLUMN_ICON ->
                        row.add(R.mipmap.ic_launcher)
                    DocumentsContract.Root.COLUMN_AVAILABLE_BYTES ->
                        row.add(-1L)
                    else ->
                        row.add(null)
                }
            }
        }

        // Notify changes when the cursor is used again.
        cursor.setNotificationUri(
            context!!.contentResolver,
            DocumentsContract.buildRootsUri(context!!.packageName + ".documents")
        )

        return cursor
    }

    // -------------------------------------------------------------------------
    // Document queries
    // -------------------------------------------------------------------------

    /**
     * Returns metadata for a single document identified by [documentId].
     */
    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val cols = projection ?: DEFAULT_DOCUMENT_PROJECTION
        val cursor = MatrixCursor(cols)

        val parsed = parseDocumentId(documentId)
            ?: return cursor // malformed ID → empty result

        val (provider, path) = parsed
        val isRoot = path == "/" || path.isEmpty()
        val name = if (isRoot) {
            // Root document name = provider label
            readConnectedProviders()
                .firstOrNull { it.provider == provider }
                ?.label
                ?: provider
        } else {
            path.substringAfterLast('/')
        }

        val docFlags = if (isRoot) {
            DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE
        } else {
            DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                    DocumentsContract.Document.FLAG_SUPPORTS_DELETE or
                    DocumentsContract.Document.FLAG_SUPPORTS_RENAME or
                    DocumentsContract.Document.FLAG_SUPPORTS_COPY or
                    DocumentsContract.Document.FLAG_SUPPORTS_MOVE
        }

        addDocumentRow(
            cursor, cols,
            documentId = documentId,
            name = name,
            mimeType = if (isRoot) DocumentsContract.Document.MIME_TYPE_DIR
                       else mimeTypeFor(name, false),
            size = 0L,
            lastModified = System.currentTimeMillis(),
            flags = docFlags
        )

        return cursor
    }

    /**
     * Lists the children of [parentDocumentId].
     * Delegates to the Flutter engine via MethodChannel.
     */
    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<String>?,
        sortOrder: String?
    ): Cursor {
        val cols = projection ?: DEFAULT_DOCUMENT_PROJECTION
        val cursor = MatrixCursor(cols)

        val parsed = parseDocumentId(parentDocumentId) ?: return cursor
        val (provider, path) = parsed

        Log.d(TAG, "queryChildDocuments provider=$provider path=$path")

        val result = invokeChannelSync("listDirectory", mapOf(
            "provider" to provider,
            "path" to path
        ))

        if (result is List<*>) {
            @Suppress("UNCHECKED_CAST")
            for (item in result as List<Map<String, Any?>>) {
                val name = item["name"] as? String ?: continue
                val isDir = item["isDirectory"] as? Boolean ?: false
                val size = (item["size"] as? Number)?.toLong() ?: 0L
                val modified = (item["lastModified"] as? Number)?.toLong()
                    ?: System.currentTimeMillis()

                val childPath = if (path.endsWith("/")) "$path$name" else "$path/$name"
                val childId = makeDocumentId(provider, childPath)

                val docFlags = if (isDir) {
                    DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE
                } else {
                    DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                            DocumentsContract.Document.FLAG_SUPPORTS_DELETE or
                            DocumentsContract.Document.FLAG_SUPPORTS_RENAME
                }

                addDocumentRow(
                    cursor, cols,
                    documentId = childId,
                    name = name,
                    mimeType = mimeTypeFor(name, isDir),
                    size = size,
                    lastModified = modified,
                    flags = docFlags
                )
            }
        }

        // Register for change notifications.
        cursor.setNotificationUri(
            context!!.contentResolver,
            DocumentsContract.buildChildDocumentsUri(
                context!!.packageName + ".documents",
                parentDocumentId
            )
        )

        return cursor
    }

    // -------------------------------------------------------------------------
    // File I/O
    // -------------------------------------------------------------------------

    /**
     * Opens a document for reading or writing.
     * Streams content via a pipe-backed ParcelFileDescriptor.
     */
    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val parsed = parseDocumentId(documentId)
            ?: throw FileNotFoundException("Invalid document ID: $documentId")
        val (provider, path) = parsed

        Log.d(TAG, "openDocument provider=$provider path=$path mode=$mode")

        val accessMode = ParcelFileDescriptor.parseMode(mode)
        val isWrite = (accessMode and ParcelFileDescriptor.MODE_WRITE_ONLY) != 0 ||
                (accessMode and ParcelFileDescriptor.MODE_READ_WRITE) != 0

        return if (isWrite) {
            openDocumentForWrite(provider, path)
        } else {
            openDocumentForRead(provider, path, signal)
        }
    }

    private fun openDocumentForRead(
        provider: String,
        path: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        Thread {
            try {
                val data = invokeChannelSync("readFile", mapOf(
                    "provider" to provider,
                    "path" to path
                ))
                if (data is ByteArray) {
                    ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { out ->
                        out.write(data)
                    }
                } else {
                    writeSide.closeWithError("Failed to read file data")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading file $path", e)
                try { writeSide.closeWithError(e.message ?: "read error") } catch (_: Exception) {}
            }
        }.start()

        return readSide
    }

    private fun openDocumentForWrite(provider: String, path: String): ParcelFileDescriptor {
        // Write to a temp file, then upload on close.
        val tempFile = File.createTempFile("crisp_upload_", null, context!!.cacheDir)
        return ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_WRITE,
            Handler(Looper.getMainLooper())) { e ->
            if (e == null) {
                // Upload the written content.
                try {
                    val bytes = tempFile.readBytes()
                    invokeChannelSync("writeFile", mapOf(
                        "provider" to provider,
                        "path" to path,
                        "data" to bytes
                    ))
                    // Notify listeners of the change.
                    notifyDocumentChanged(makeDocumentId(provider, path))
                } catch (ex: Exception) {
                    Log.e(TAG, "Error uploading file $path", ex)
                }
            }
            tempFile.delete()
        }
    }

    // -------------------------------------------------------------------------
    // Mutating operations
    // -------------------------------------------------------------------------

    /**
     * Creates a new file or directory under [parentDocumentId].
     */
    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String
    ): String {
        val parsed = parseDocumentId(parentDocumentId)
            ?: throw UnsupportedOperationException("Invalid parent ID: $parentDocumentId")
        val (provider, parentPath) = parsed

        val newPath = if (parentPath.endsWith("/"))
            "$parentPath$displayName"
        else
            "$parentPath/$displayName"

        val isDir = mimeType == DocumentsContract.Document.MIME_TYPE_DIR

        Log.d(TAG, "createDocument provider=$provider path=$newPath isDir=$isDir")

        invokeChannelSync("createDocument", mapOf(
            "provider" to provider,
            "path" to newPath,
            "isDirectory" to isDir,
            "mimeType" to mimeType
        ))

        val newDocumentId = makeDocumentId(provider, newPath)
        notifyDocumentChanged(parentDocumentId)
        return newDocumentId
    }

    /**
     * Deletes the document identified by [documentId].
     */
    override fun deleteDocument(documentId: String) {
        val parsed = parseDocumentId(documentId)
            ?: throw UnsupportedOperationException("Invalid document ID: $documentId")
        val (provider, path) = parsed

        Log.d(TAG, "deleteDocument provider=$provider path=$path")

        invokeChannelSync("deleteDocument", mapOf(
            "provider" to provider,
            "path" to path
        ))

        notifyDocumentChanged(documentId)
    }

    /**
     * Renames the document identified by [documentId].
     */
    override fun renameDocument(documentId: String, displayName: String): String {
        val parsed = parseDocumentId(documentId)
            ?: throw UnsupportedOperationException("Invalid document ID: $documentId")
        val (provider, path) = parsed

        val parentPath = path.substringBeforeLast('/', "/")
        val newPath = if (parentPath.isEmpty() || parentPath == "/")
            "/$displayName"
        else
            "$parentPath/$displayName"

        Log.d(TAG, "renameDocument provider=$provider path=$path -> $newPath")

        invokeChannelSync("renameDocument", mapOf(
            "provider" to provider,
            "oldPath" to path,
            "newPath" to newPath,
            "newName" to displayName
        ))

        val newDocumentId = makeDocumentId(provider, newPath)
        notifyDocumentChanged(documentId)
        return newDocumentId
    }

    // -------------------------------------------------------------------------
    // MethodChannel bridge (synchronous wrapper)
    // -------------------------------------------------------------------------

    /**
     * Invokes a Flutter MethodChannel method synchronously by posting to the
     * main looper and waiting with a CountDownLatch.
     *
     * This is necessary because DocumentsProvider callbacks run on a
     * background thread, but MethodChannel must be called from the main thread.
     */
    private fun invokeChannelSync(method: String, args: Map<String, Any?>): Any? {
        val ctx = context ?: return null
        val flutterEngine = FlutterEngineHolder.engine ?: run {
            Log.w(TAG, "Flutter engine not available for $method")
            return null
        }

        val resultRef = AtomicReference<Any?>()
        val latch = CountDownLatch(1)

        Handler(Looper.getMainLooper()).post {
            try {
                val channel = io.flutter.plugin.common.MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    CHANNEL_NAME
                )
                channel.invokeMethod(method, args, object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        resultRef.set(result)
                        latch.countDown()
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e(TAG, "Channel error $method: $errorCode $errorMessage")
                        latch.countDown()
                    }
                    override fun notImplemented() {
                        Log.w(TAG, "Method not implemented: $method")
                        latch.countDown()
                    }
                })
            } catch (e: Exception) {
                Log.e(TAG, "Failed to invoke channel method $method", e)
                latch.countDown()
            }
        }

        latch.await(CHANNEL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        return resultRef.get()
    }

    // -------------------------------------------------------------------------
    // SharedPreferences helpers
    // -------------------------------------------------------------------------

    /**
     * Reads the list of connected providers from SharedPreferences.
     * Written by DocumentsProviderBridge in Dart.
     */
    fun readConnectedProviders(): List<ProviderEntry> {
        val ctx = context ?: return emptyList()
        val prefs: SharedPreferences = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(PREFS_KEY_PROVIDERS, null) ?: return emptyList()

        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.getJSONObject(i)
                val provider = obj.optString("provider").takeIf { it.isNotEmpty() }
                    ?: return@mapNotNull null
                val label = obj.optString("label", provider)
                val rootId = obj.optString("rootDocumentId", "$provider:/")
                ProviderEntry(provider = provider, label = label, rootDocumentId = rootId)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse connected providers JSON", e)
            emptyList()
        }
    }

    // -------------------------------------------------------------------------
    // Change notification helpers
    // -------------------------------------------------------------------------

    /** Notify the system that a document has changed. */
    private fun notifyDocumentChanged(documentId: String) {
        val ctx = context ?: return
        val uri = DocumentsContract.buildDocumentUri(
            ctx.packageName + ".documents",
            documentId
        )
        ctx.contentResolver.notifyChange(uri, null)
    }

    /** Notify the system that the root list has changed (called by the bridge). */
    fun notifyRootsChanged() {
        val ctx = context ?: return
        val uri = DocumentsContract.buildRootsUri(ctx.packageName + ".documents")
        ctx.contentResolver.notifyChange(uri, null)
        Log.d(TAG, "Roots changed notification sent")
    }

    // -------------------------------------------------------------------------
    // MatrixCursor helpers
    // -------------------------------------------------------------------------

    private fun addDocumentRow(
        cursor: MatrixCursor,
        cols: Array<String>,
        documentId: String,
        name: String,
        mimeType: String,
        size: Long,
        lastModified: Long,
        flags: Int
    ) {
        val row = cursor.newRow()
        for (col in cols) {
            when (col) {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID -> row.add(documentId)
                DocumentsContract.Document.COLUMN_DISPLAY_NAME -> row.add(name)
                DocumentsContract.Document.COLUMN_MIME_TYPE -> row.add(mimeType)
                DocumentsContract.Document.COLUMN_SIZE -> row.add(size)
                DocumentsContract.Document.COLUMN_LAST_MODIFIED -> row.add(lastModified)
                DocumentsContract.Document.COLUMN_FLAGS -> row.add(flags)
                else -> row.add(null)
            }
        }
    }
}

/**
 * Holds a reference to the active Flutter engine so the DocumentsProvider
 * can invoke MethodChannel calls.  Must be set from MainActivity when the
 * engine is ready.
 */
object FlutterEngineHolder {
    @Volatile
    var engine: io.flutter.embedding.engine.FlutterEngine? = null
}
