package com.example.optcare_app

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                LEGACY_PERMISSION_CHECK_METHOD -> {
                    result.success(Build.VERSION.SDK_INT <= Build.VERSION_CODES.P)
                }

                SAVE_JPEG_METHOD -> {
                    val jpegBytes = call.arguments as? ByteArray
                    if (jpegBytes == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "Expected JPEG bytes.",
                            null,
                        )
                    } else {
                        try {
                            validateJpeg(jpegBytes)
                            saveJpeg(jpegBytes, result)
                        } catch (error: IllegalArgumentException) {
                            result.error("INVALID_IMAGE", error.message, null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveJpeg(jpegBytes: ByteArray, result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "WRITE_PERMISSION_DENIED",
                "Legacy external storage permission is required.",
                null,
            )
            return
        }

        ioExecutor.execute {
            try {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(jpegBytes)
                } else {
                    saveWithLegacyStorage(jpegBytes)
                }
                mainHandler.post { result.success(uri.toString()) }
            } catch (error: SecurityException) {
                mainHandler.post {
                    result.error(
                        "WRITE_PERMISSION_DENIED",
                        "Storage permission is required to save this photo.",
                        null,
                    )
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "GALLERY_SAVE_FAILED",
                        "The photo could not be saved to Gallery.",
                        null,
                    )
                }
            }
        }
    }

    private fun validateJpeg(bytes: ByteArray) {
        require(bytes.isNotEmpty()) { "JPEG data is empty." }
        require(bytes.size <= MAX_JPEG_BYTES) { "JPEG data exceeds the size limit." }
        require(
            bytes.size >= 5 &&
                bytes[0] == 0xFF.toByte() &&
                bytes[1] == 0xD8.toByte() &&
                bytes[2] == 0xFF.toByte() &&
                bytes[bytes.size - 2] == 0xFF.toByte() &&
                bytes[bytes.size - 1] == 0xD9.toByte(),
        ) { "JPEG signature is invalid." }
    }

    private fun saveWithMediaStore(bytes: ByteArray): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, uniqueFileName())
            put(MediaStore.Images.Media.MIME_TYPE, JPEG_MIME_TYPE)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/$GALLERY_DIRECTORY",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        val uri = contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IOException("MediaStore did not create an image row.")

        try {
            val output = contentResolver.openOutputStream(uri, "w")
                ?: throw IOException("Could not open the Gallery image stream.")
            output.use {
                it.write(bytes)
                it.flush()
            }

            val publishedRows = contentResolver.update(
                uri,
                ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                },
                null,
                null,
            )
            if (publishedRows != 1) {
                throw IOException("MediaStore did not publish the image.")
            }
            return uri
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveWithLegacyStorage(bytes: ByteArray): Uri {
        val picturesDirectory = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_PICTURES,
        )
        val targetDirectory = File(picturesDirectory, GALLERY_DIRECTORY)
        if (!targetDirectory.isDirectory && !targetDirectory.mkdirs()) {
            throw IOException("Could not create the Gallery directory.")
        }

        val imageFile = File(targetDirectory, uniqueFileName())
        try {
            FileOutputStream(imageFile).use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            return scanLegacyImage(imageFile)
        } catch (error: Exception) {
            if (imageFile.exists()) {
                imageFile.delete()
            }
            throw error
        }
    }

    private fun scanLegacyImage(imageFile: File): Uri {
        val scanCompleted = CountDownLatch(1)
        var scannedUri: Uri? = null
        MediaScannerConnection.scanFile(
            this,
            arrayOf(imageFile.absolutePath),
            arrayOf(JPEG_MIME_TYPE),
        ) { _, uri ->
            scannedUri = uri
            scanCompleted.countDown()
        }

        try {
            if (!scanCompleted.await(MEDIA_SCAN_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw IOException("Gallery media scan timed out.")
            }
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IOException("Gallery media scan was interrupted.", error)
        }

        return scannedUri ?: throw IOException("Gallery did not index the image.")
    }

    private fun uniqueFileName(): String =
        "TryOn_${System.currentTimeMillis()}_${UUID.randomUUID()}.jpg"

    override fun onDestroy() {
        ioExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_NAME =
            "com.gonzalesvisionclinic.optcare_app/try_on_gallery"
        private const val LEGACY_PERMISSION_CHECK_METHOD =
            "requiresLegacyStoragePermission"
        private const val SAVE_JPEG_METHOD = "saveTryOnJpeg"
        private const val GALLERY_DIRECTORY = "GonzalesVisionClinic"
        private const val JPEG_MIME_TYPE = "image/jpeg"
        private const val MAX_JPEG_BYTES = 10 * 1024 * 1024
        private const val MEDIA_SCAN_TIMEOUT_SECONDS = 20L
    }
}
