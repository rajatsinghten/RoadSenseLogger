package ai.roadsense.roadsense_logger.export

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.File
import java.io.IOException

/**
 * Copies a finished export archive into the public Downloads folder under
 * [SUBFOLDER] (FR-070).
 *
 * - Android 10+ (API 29): MediaStore Downloads collection; no storage
 *   permission is needed.
 * - Android 8–9 (API 26–28): the public Downloads directory, which requires
 *   `WRITE_EXTERNAL_STORAGE` (declared with maxSdkVersion 28 only).
 *
 * Runs blocking I/O: call it off the main thread.
 */
class DownloadsExporter(private val context: Context) {

    /** Copies [source] as [displayName]; returns the user-visible location. */
    @Throws(IOException::class)
    fun save(source: File, displayName: String): String {
        if (!source.isFile) throw IOException("Archive not found: ${source.path}")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(source, displayName)
        } else {
            saveLegacy(source, displayName)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveWithMediaStore(source: File, displayName: String): String {
        val resolver = context.contentResolver
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER"
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, MIME_ZIP)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            // Hidden from other apps until the copy completes.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create $displayName in Downloads")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("Could not open $displayName for writing")
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (error: Exception) {
            // Never leave a truncated, pending file behind.
            resolver.delete(uri, null, null)
            throw IOException("Saving $displayName to Downloads failed: ${error.message}", error)
        }
        val savedName = resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        return "$relativePath/${savedName ?: displayName}"
    }

    @Suppress("DEPRECATION") // Public directory API is the only option below API 29.
    private fun saveLegacy(source: File, displayName: String): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            SUBFOLDER,
        )
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw IOException("Could not create ${dir.path}")
        }
        val target = uniqueTarget(dir, displayName)
        val partial = File(dir, "${target.name}.part")
        try {
            source.copyTo(partial, overwrite = true)
            if (!partial.renameTo(target)) throw IOException("Could not finalize ${target.name}")
        } catch (error: Exception) {
            partial.delete()
            throw IOException("Saving $displayName to Downloads failed: ${error.message}", error)
        }
        return "${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER/${target.name}"
    }

    /** Appends " (n)" before the extension instead of overwriting an export. */
    private fun uniqueTarget(dir: File, displayName: String): File {
        val base = displayName.substringBeforeLast('.')
        val ext = displayName.substringAfterLast('.', "")
        var candidate = File(dir, displayName)
        var n = 1
        while (candidate.exists()) {
            candidate = File(dir, if (ext.isEmpty()) "$base ($n)" else "$base ($n).$ext")
            n++
        }
        return candidate
    }

    companion object {
        const val SUBFOLDER = "RoadSense"
        private const val MIME_ZIP = "application/zip"
    }
}
