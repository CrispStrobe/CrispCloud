// android/app/src/main/kotlin/com/example/internxt_flutter/SAFHandler.kt
//
// Handles the "com.example.crisp_cloud/saf" MethodChannel on the Android side.
// Registered by MainActivity.

package com.example.internxt_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL = "com.example.crisp_cloud/saf"

/**
 * Registers the SAF MethodChannel and manages the Android Activity Result API
 * launchers required for document/folder pickers.
 *
 * Usage — call [register] from [MainActivity.configureFlutterEngine].
 */
class SAFHandler(private val activity: FlutterFragmentActivity) {

    // Pending result callback set by the MethodChannel call, consumed once the
    // Activity Result arrives.
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCall: String? = null

    // Launcher for ACTION_OPEN_DOCUMENT_TREE
    private val treeLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            handleTreeResult(result)
        }

    // Launcher for ACTION_OPEN_DOCUMENT (single)
    private val documentLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            handleDocumentResult(result)
        }

    // Launcher for ACTION_OPEN_DOCUMENT (multiple)
    private val multiDocumentLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            handleMultiDocumentResult(result)
        }

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocumentTree" -> openDocumentTree(call, result)
                "openDocument"     -> openDocument(call, result, multiple = false)
                "openDocuments"    -> openDocument(call, result, multiple = true)
                "listFolder"       -> listFolder(call, result)
                else               -> result.notImplemented()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Method handlers
    // -------------------------------------------------------------------------

    private fun openDocumentTree(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("BUSY", "Another SAF picker is already open", null)
            return
        }
        pendingResult = result
        pendingCall = "openDocumentTree"

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            val initialUri = call.argument<String>("initialUri")
            if (initialUri != null) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
            }
        }
        treeLauncher.launch(intent)
    }

    private fun openDocument(
        call: MethodCall,
        result: MethodChannel.Result,
        multiple: Boolean,
    ) {
        if (pendingResult != null) {
            result.error("BUSY", "Another SAF picker is already open", null)
            return
        }
        pendingResult = result
        pendingCall = if (multiple) "openDocuments" else "openDocument"

        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: listOf("*/*")

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            if (mimeTypes.size == 1) {
                type = mimeTypes[0]
            } else {
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
        }

        if (multiple) {
            multiDocumentLauncher.launch(intent)
        } else {
            documentLauncher.launch(intent)
        }
    }

    private fun listFolder(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }

        try {
            val treeUri = Uri.parse(uriString)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )

            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            )

            val cursor = activity.contentResolver.query(
                childrenUri, projection, null, null, null,
            )

            val items = mutableListOf<Map<String, Any?>>()
            cursor?.use {
                val idCol = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameCol = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeCol = it.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeCol = it.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)

                while (it.moveToNext()) {
                    val docId = it.getString(idCol)
                    val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    items.add(
                        mapOf(
                            "uri"         to docUri.toString(),
                            "displayName" to (it.getString(nameCol) ?: ""),
                            "mimeType"    to (it.getString(mimeCol) ?: "*/*"),
                            "size"        to (if (sizeCol >= 0) it.getLong(sizeCol) else -1L),
                        )
                    )
                }
            }

            result.success(items)
        } catch (e: Exception) {
            result.error("LIST_ERROR", e.message, null)
        }
    }

    // -------------------------------------------------------------------------
    // Activity result handlers
    // -------------------------------------------------------------------------

    private fun handleTreeResult(activityResult: ActivityResult) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingCall = null

        if (activityResult.resultCode != Activity.RESULT_OK) {
            pending.success(null) // user cancelled
            return
        }

        val uri = activityResult.data?.data
        if (uri == null) {
            pending.error("NO_URI", "No URI returned from tree picker", null)
            return
        }

        // Persist permission so we can access the folder across app restarts
        activity.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )

        val displayName = resolveDisplayName(uri) ?: uri.lastPathSegment ?: uri.toString()

        pending.success(
            mapOf(
                "uri"         to uri.toString(),
                "displayName" to displayName,
            )
        )
    }

    private fun handleDocumentResult(activityResult: ActivityResult) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingCall = null

        if (activityResult.resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }

        val uri = activityResult.data?.data
        if (uri == null) {
            pending.error("NO_URI", "No URI returned from document picker", null)
            return
        }

        pending.success(resolveFileMetadata(uri))
    }

    private fun handleMultiDocumentResult(activityResult: ActivityResult) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingCall = null

        if (activityResult.resultCode != Activity.RESULT_OK) {
            pending.success(emptyList<Map<String, Any?>>())
            return
        }

        val data = activityResult.data
        val items = mutableListOf<Map<String, Any?>>()

        if (data?.clipData != null) {
            val clip = data.clipData!!
            for (i in 0 until clip.itemCount) {
                val uri = clip.getItemAt(i).uri ?: continue
                items.add(resolveFileMetadata(uri))
            }
        } else if (data?.data != null) {
            items.add(resolveFileMetadata(data.data!!))
        }

        pending.success(items)
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun resolveFileMetadata(uri: Uri): Map<String, Any?> {
        var displayName = ""
        var mimeType = "*/*"
        var size = -1L

        try {
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            )
            activity.contentResolver.query(uri, projection, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    displayName = c.getString(c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)) ?: ""
                    mimeType    = c.getString(c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)) ?: "*/*"
                    size        = c.getLong(c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE))
                }
            }
        } catch (_: Exception) {
            // Fall back to URI-derived name
            displayName = uri.lastPathSegment ?: uri.toString()
        }

        return mapOf(
            "uri"         to uri.toString(),
            "displayName" to displayName,
            "mimeType"    to mimeType,
            "size"        to size,
        )
    }

    private fun resolveDisplayName(uri: Uri): String? {
        return try {
            activity.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
