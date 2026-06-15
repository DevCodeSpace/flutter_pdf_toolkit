package com.example.flutter_pdf_toolkit

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

class FlutterPdfToolkitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_pdf_toolkit")
        channel.setMethodCallHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            "flutter_pdf_toolkit/native_view",
            PdfNativeViewFactory(binding.binaryMessenger)
        )
        
        // Initialize PDFBox resource loader early
        try {
            PDFBoxResourceLoader.init(context)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "mergePdfs" -> {
                val paths = call.argument<List<String>>("paths")
                val outputPath = call.argument<String>("outputPath")
                if (paths == null || outputPath == null) {
                    result.error("INVALID_ARGUMENTS", "paths and outputPath are required", null)
                    return
                }

                executor.execute {
                    // Create parent directories
                    val outputFile = File(outputPath)
                    outputFile.parentFile?.mkdirs()

                    val success = try {
                        val merger = PDFMergerUtility()
                        merger.destinationFileName = outputPath
                        for (path in paths) {
                            merger.addSource(File(path))
                        }
                        // setupTempFileOnly is memory efficient for Android
                        merger.mergeDocuments(MemoryUsageSetting.setupTempFileOnly())
                        true
                    } catch (e: Exception) {
                        e.printStackTrace()
                        false
                    }

                    mainHandler.post {
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "getPdfPageCount" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARGUMENTS", "path is required", null)
                    return
                }

                executor.execute {
                    val pageCount = try {
                        PDDocument.load(File(path)).use { it.numberOfPages }
                    } catch (e: Exception) {
                        e.printStackTrace()
                        null
                    }

                    mainHandler.post {
                        result.success(pageCount)
                    }
                }
            }
            "splitPdf" -> {
                val path = call.argument<String>("path")
                val outputDirectory = call.argument<String>("outputDirectory")
                val pageRanges = call.argument<List<List<*>>>("pageRanges")
                val prefix = call.argument<String>("outputFileNamePrefix") ?: "split"
                if (path == null || outputDirectory == null || pageRanges == null) {
                    result.error("INVALID_ARGUMENTS", "path, outputDirectory and pageRanges are required", null)
                    return
                }

                executor.execute {
                    val outputDir = File(outputDirectory)
                    outputDir.mkdirs()
                    val outputPaths = mutableListOf<String>()

                    val success = try {
                        PDDocument.load(File(path)).use { source ->
                            val pageCount = source.numberOfPages
                            for ((index, range) in pageRanges.withIndex()) {
                                val start = ((range.getOrNull(0) as? Number)?.toInt() ?: 1).coerceIn(1, pageCount)
                                val end = ((range.getOrNull(1) as? Number)?.toInt() ?: pageCount).coerceIn(start, pageCount)

                                val outputFile = File(outputDir, "${prefix}_${index + 1}.pdf")
                                PDDocument().use { target ->
                                    for (pageIndex in (start - 1) until end) {
                                        target.importPage(source.getPage(pageIndex))
                                    }
                                    target.save(outputFile)
                                }
                                outputPaths.add(outputFile.absolutePath)
                            }
                        }
                        true
                    } catch (e: Exception) {
                        e.printStackTrace()
                        false
                    }

                    mainHandler.post {
                        if (success) {
                            result.success(outputPaths)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "reorderPdf" -> {
                val path = call.argument<String>("path")
                val outputPath = call.argument<String>("outputPath")
                val pageOrder = call.argument<List<*>>("pageOrder")
                if (path == null || outputPath == null || pageOrder == null) {
                    result.error("INVALID_ARGUMENTS", "path, outputPath and pageOrder are required", null)
                    return
                }

                executor.execute {
                    val outputFile = File(outputPath)
                    outputFile.parentFile?.mkdirs()

                    val success = try {
                        PDDocument.load(File(path)).use { source ->
                            val pageCount = source.numberOfPages
                            PDDocument().use { target ->
                                for (entry in pageOrder) {
                                    val pageIndex = (((entry as Number).toInt()) - 1).coerceIn(0, pageCount - 1)
                                    target.importPage(source.getPage(pageIndex))
                                }
                                target.save(outputFile)
                            }
                        }
                        true
                    } catch (e: Exception) {
                        e.printStackTrace()
                        false
                    }

                    mainHandler.post {
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "downloadPdf" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")
                if (sourcePath == null || fileName == null) {
                    result.error("INVALID_ARGUMENTS", "sourcePath and fileName are required", null)
                    return
                }
                downloadPdf(sourcePath, fileName, result)
            }
            "signPdf" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                val signatureBytes = call.argument<ByteArray>("signatureBytes")
                val pageNumber = call.argument<Int>("pageNumber")
                val xRatio = call.argument<Double>("xRatio")
                val yRatio = call.argument<Double>("yRatio")
                val widthRatio = call.argument<Double>("widthRatio")
                val heightRatio = call.argument<Double>("heightRatio")
                if (sourcePath == null || outputPath == null || signatureBytes == null || pageNumber == null ||
                    xRatio == null || yRatio == null || widthRatio == null || heightRatio == null
                ) {
                    result.error("INVALID_ARGUMENTS", "sourcePath, outputPath, signatureBytes, pageNumber, xRatio, yRatio, widthRatio and heightRatio are required", null)
                    return
                }

                executor.execute {
                    val success = stampImageOnPdf(sourcePath, outputPath, signatureBytes, pageNumber, xRatio, yRatio, widthRatio, heightRatio)

                    mainHandler.post {
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "addImageToPdf" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val pageNumber = call.argument<Int>("pageNumber")
                val xRatio = call.argument<Double>("xRatio")
                val yRatio = call.argument<Double>("yRatio")
                val widthRatio = call.argument<Double>("widthRatio")
                val heightRatio = call.argument<Double>("heightRatio")
                if (sourcePath == null || outputPath == null || imageBytes == null || pageNumber == null ||
                    xRatio == null || yRatio == null || widthRatio == null || heightRatio == null
                ) {
                    result.error("INVALID_ARGUMENTS", "sourcePath, outputPath, imageBytes, pageNumber, xRatio, yRatio, widthRatio and heightRatio are required", null)
                    return
                }

                executor.execute {
                    val success = stampImageOnPdf(sourcePath, outputPath, imageBytes, pageNumber, xRatio, yRatio, widthRatio, heightRatio)

                    mainHandler.post {
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            "imagesToPdf" -> {
                val imagePaths = call.argument<List<String>>("imagePaths")
                val outputPath = call.argument<String>("outputPath")
                if (imagePaths == null || outputPath == null) {
                    result.error("INVALID_ARGUMENTS", "imagePaths and outputPath are required", null)
                    return
                }

                executor.execute {
                    val outputFile = File(outputPath)
                    outputFile.parentFile?.mkdirs()

                    val success = try {
                        PDDocument().use { document ->
                            for (imagePath in imagePaths) {
                                val bitmap = BitmapFactory.decodeFile(imagePath)
                                    ?: throw IllegalArgumentException("Could not decode image: $imagePath")
                                val page = PDPage(PDRectangle(bitmap.width.toFloat(), bitmap.height.toFloat()))
                                document.addPage(page)
                                val pdImage = LosslessFactory.createFromImage(document, bitmap)
                                PDPageContentStream(document, page).use { contentStream ->
                                    contentStream.drawImage(pdImage, 0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
                                }
                            }
                            document.save(outputFile)
                        }
                        true
                    } catch (e: Exception) {
                        e.printStackTrace()
                        false
                    }

                    mainHandler.post {
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.success(null)
                        }
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun stampImageOnPdf(
        sourcePath: String,
        outputPath: String,
        imageBytes: ByteArray,
        pageNumber: Int,
        xRatio: Double,
        yRatio: Double,
        widthRatio: Double,
        heightRatio: Double
    ): Boolean {
        return try {
            PDDocument.load(File(sourcePath)).use { document ->
                val pageIndex = (pageNumber - 1).coerceIn(0, document.numberOfPages - 1)
                val page = document.getPage(pageIndex)
                val mediaBox = page.mediaBox
                val pageWidth = mediaBox.width
                val pageHeight = mediaBox.height

                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: throw IllegalArgumentException("Could not decode image")
                val pdImage = LosslessFactory.createFromImage(document, bitmap)

                val w = (widthRatio * pageWidth).toFloat()
                val h = (heightRatio * pageHeight).toFloat()
                val x = (xRatio * pageWidth).toFloat()
                val y = (pageHeight - (yRatio * pageHeight) - h).toFloat()

                PDPageContentStream(document, page, PDPageContentStream.AppendMode.APPEND, true, true).use { contentStream ->
                    contentStream.drawImage(pdImage, x, y, w, h)
                }

                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                document.save(outputFile)
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun downloadPdf(sourcePath: String, fileName: String, result: MethodChannel.Result) {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            result.error("FILE_NOT_FOUND", "Source file not found", null)
            return
        }

        executor.execute {
            val success = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = context.contentResolver
                    val contentValues = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    }

                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                    if (uri != null) {
                        resolver.openOutputStream(uri)?.use { outputStream ->
                            FileInputStream(sourceFile).use { inputStream ->
                                inputStream.copyTo(outputStream)
                            }
                        }
                        true
                    } else {
                        false
                    }
                } else {
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    if (!downloadsDir.exists()) {
                        downloadsDir.mkdirs()
                    }
                    val destinationFile = File(downloadsDir, fileName)
                    FileOutputStream(destinationFile).use { outputStream ->
                        FileInputStream(sourceFile).use { inputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    }
                    true
                }
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }

            mainHandler.post {
                result.success(success)
            }
        }
    }
}
