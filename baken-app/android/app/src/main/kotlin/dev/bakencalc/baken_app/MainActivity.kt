package dev.bakencalc.baken_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * バックアップ用に、利用者が選んだフォルダ（Google ドライブのフォルダも可）へ
 * ファイルを書く。Storage Access Framework を使うので、ストレージ権限はいらない。
 */
class MainActivity : FlutterActivity() {
    private val pickFolderRequest = 4101
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "baken/backup")
            .setMethodCallHandler { call, result ->
                try {
                    handle(call, result)
                } catch (e: Exception) {
                    result.error("backup_failed", e.message ?: e.toString(), null)
                }
            }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> {
                if (pendingPick != null) {
                    result.error("busy", "フォルダを選んでいる途中です", null)
                    return
                }
                pendingPick = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                }
                startActivityForResult(intent, pickFolderRequest)
            }
            "writeFile" -> {
                val tree = Uri.parse(call.argument<String>("tree"))
                val name = call.argument<String>("name")!!
                val content = call.argument<String>("content")!!.toByteArray(Charsets.UTF_8)
                writeFile(tree, name, content)
                result.success(null)
            }
            "listFiles" -> {
                val tree = Uri.parse(call.argument<String>("tree"))
                result.success(listChildren(tree).keys.toList())
            }
            "deleteFile" -> {
                val tree = Uri.parse(call.argument<String>("tree"))
                val name = call.argument<String>("name")!!
                listChildren(tree)[name]?.let {
                    DocumentsContract.deleteDocument(contentResolver, it)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFolderRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
        } catch (e: Exception) {
            result.error("pick_failed", e.message ?: e.toString(), null)
        }
    }

    private fun folderUri(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun folderName(tree: Uri): String {
        contentResolver.query(
            folderUri(tree),
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { c ->
            if (c.moveToFirst()) return c.getString(0) ?: "フォルダ"
        }
        return "フォルダ"
    }

    /** フォルダ直下のファイル名 → ドキュメント URI */
    private fun listChildren(tree: Uri): Map<String, Uri> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val out = mutableMapOf<String, Uri>()
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0) ?: continue
                val name = c.getString(1) ?: continue
                out[name] = DocumentsContract.buildDocumentUriUsingTree(tree, id)
            }
        }
        return out
    }

    private fun writeFile(tree: Uri, name: String, bytes: ByteArray) {
        val existing = listChildren(tree)[name]
        if (existing != null) {
            // 上書き。切り詰めに対応しないフォルダでは消して作り直す
            val written = try {
                contentResolver.openOutputStream(existing, "wt")?.use { it.write(bytes) } != null
            } catch (e: Exception) {
                false
            }
            if (written) return
            DocumentsContract.deleteDocument(contentResolver, existing)
        }
        val created = DocumentsContract.createDocument(
            contentResolver,
            folderUri(tree),
            "application/json",
            name,
        ) ?: throw IllegalStateException("ファイルを作れませんでした")
        contentResolver.openOutputStream(created, "w")?.use { it.write(bytes) }
            ?: throw IllegalStateException("ファイルに書き込めませんでした")
    }
}
