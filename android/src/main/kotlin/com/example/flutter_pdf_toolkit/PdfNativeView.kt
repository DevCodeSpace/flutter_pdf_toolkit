package com.example.flutter_pdf_toolkit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.action.PDActionGoTo
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDNamedDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition

class PdfNativeView(
    private val context: Context,
    messenger: BinaryMessenger,
    private val viewId: Int,
    creationParams: Map<String, Any?>?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "flutter_pdf_toolkit_view_$viewId")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    // Separate executor for highlight-rect computation so it doesn't queue behind
    // the bulk text-extraction work and appear with a delay after a search jump.
    private val highlightExecutor = Executors.newSingleThreadExecutor()
    private val root = FrameLayout(context)
    private val verticalScroll = ScrollView(context)
    private val horizontalScroll = HorizontalScrollView(context)
    private val pagesContainer = LinearLayout(context)
    private val gestureDetector: GestureDetector
    private val scaleGestureDetector: ScaleGestureDetector

    // Set on dispose() (main thread) and checked from posted Handler callbacks that may
    // run after disposal, to avoid touching a shut-down executor or a torn-down view.
    @Volatile private var isDisposed = false

    private var renderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var decryptedFile: File? = null
    private var pageCount = 0
    private var currentPage = 1
    private var zoom = (creationParams?.get("initialZoomLevel") as? Number)?.toFloat() ?: 1f
    private var lastAppliedZoom = zoom
    private var transientScale = 1f
    private var pinchFocusX = 0f
    private var pinchFocusY = 0f
    private val singlePage = creationParams?.get("singlePage") as? Boolean ?: false
    private val vertical = (creationParams?.get("scrollDirection") as? String ?: "vertical") == "vertical"
    private val path = creationParams?.get("path") as String
    private var currentPassword = creationParams?.get("password") as? String ?: ""
    private var initialPage = (creationParams?.get("initialPage") as? Number)?.toInt() ?: 1
    private var darkMode = creationParams?.get("darkMode") as? Boolean ?: false
    private var searchMatches = listOf<SearchMatch>()
    private var currentSearchMatchIndex = 0
    private var currentSearchText = ""

    // Keyed by page number (1-based). Populated on executor; read on executor (single-thread, no races).
    private val pageTextCache = mutableMapOf<Int, String>()
    // Accessed from both main thread and executor, so use concurrent map.
    private val pageImageViews = ConcurrentHashMap<Int, ImageView>()
    private val originalBitmaps = ConcurrentHashMap<Int, Bitmap>()

    init {
        PDFBoxResourceLoader.init(context)
        channel.setMethodCallHandler(this)
        pagesContainer.orientation = if (vertical) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
        pagesContainer.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )

        verticalScroll.isFillViewport = true
        horizontalScroll.isFillViewport = true

        // Pivot at the origin so the transient pinch transform below scales/translates
        // around the content's top-left, matching the scroll-position math in applyZoom.
        pagesContainer.pivotX = 0f
        pagesContainer.pivotY = 0f

        verticalScroll.addView(horizontalScroll)
        horizontalScroll.addView(pagesContainer)

        root.addView(
            verticalScroll,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )
        applyTheme()

        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean {
                zoom = if (zoom < 1.5f) 2f else 1f
                applyZoom(preserveScrollPosition = true)
                return true
            }
        })
        scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                transientScale = 1f
                pagesContainer.translationX = 0f
                pagesContainer.translationY = 0f
                // Cache the container as a texture so the pinch transform below is GPU-composited
                // instead of re-drawing every page bitmap on each frame.
                pagesContainer.setLayerType(View.LAYER_TYPE_HARDWARE, null)
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val newZoom = (zoom * detector.scaleFactor).coerceIn(0.5f, 4f)
                val factor = if (zoom != 0f) newZoom / zoom else 1f
                zoom = newZoom

                pinchFocusX = detector.focusX
                pinchFocusY = detector.focusY
                val anchorX = pinchFocusX + horizontalScroll.scrollX
                val anchorY = pinchFocusY + verticalScroll.scrollY

                transientScale *= factor
                pagesContainer.scaleX = transientScale
                pagesContainer.scaleY = transientScale
                pagesContainer.translationX = anchorX + (pagesContainer.translationX - anchorX) * factor
                pagesContainer.translationY = anchorY + (pagesContainer.translationY - anchorY) * factor
                return true
            }

            override fun onScaleEnd(detector: ScaleGestureDetector) {
                pagesContainer.setLayerType(View.LAYER_TYPE_NONE, null)
                pagesContainer.scaleX = 1f
                pagesContainer.scaleY = 1f
                pagesContainer.translationX = 0f
                pagesContainer.translationY = 0f
                transientScale = 1f
                applyZoom(preserveScrollPosition = true, anchorX = pinchFocusX, anchorY = pinchFocusY)
            }
        })

        val touchListener = View.OnTouchListener { _, event ->
            if (event.pointerCount > 1) {
                verticalScroll.requestDisallowInterceptTouchEvent(true)
                horizontalScroll.requestDisallowInterceptTouchEvent(true)
            }
            scaleGestureDetector.onTouchEvent(event)
            gestureDetector.onTouchEvent(event)
            event.pointerCount > 1 || scaleGestureDetector.isInProgress
        }
        verticalScroll.setOnTouchListener(touchListener)
        horizontalScroll.setOnTouchListener(touchListener)

        loadDocument()
    }

    private fun loadDocument() {
        loadDocumentWithPassword(currentPassword, currentPassword.isNotEmpty())
    }

    private fun loadDocumentWithPassword(pwd: String, isRetry: Boolean) {
        executor.execute {
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                    throw IllegalStateException("PdfRenderer requires API 21+")
                }

                var decryptedFileToUse: File? = null
                var usePath = path

                // Attempt to load with the password
                try {
                    PDDocument.load(File(path), pwd).use { doc ->
                        if (doc.isEncrypted) {
                            val temp = File(context.cacheDir, "pdf_decrypted_${System.currentTimeMillis()}.pdf")
                            doc.setAllSecurityToBeRemoved(true)
                            doc.save(temp)
                            decryptedFileToUse = temp
                            usePath = temp.absolutePath
                        }
                    }
                } catch (e: Exception) {
                    val msg = e.message ?: ""
                    if (msg.lowercase().contains("password") || msg.lowercase().contains("encrypted") || msg.lowercase().contains("decrypt") || e is java.io.IOException) {
                        // Password is required/incorrect
                        promptPassword(isRetry)
                        return@execute
                    } else {
                        throw e
                    }
                }

                // If loading succeeded, we initialize PdfRenderer
                val fd = ParcelFileDescriptor.open(File(usePath), ParcelFileDescriptor.MODE_READ_ONLY)
                val renderer = synchronized(pdfiumLock) { PdfRenderer(fd) }
                this.fileDescriptor = fd
                this.renderer = renderer
                this.pageCount = renderer.pageCount
                this.decryptedFile = decryptedFileToUse
                this.currentPassword = pwd

                mainHandler.post {
                    if (isDisposed) return@post
                    renderPages()
                    sendReady()
                    sendPageChanged()
                    if (initialPage > 1) {
                        jumpToPageInternal(initialPage)
                    }
                }

                startTextExtraction()
            } catch (e: Exception) {
                val msg = e.message ?: "Failed to open PDF"
                mainHandler.post {
                    if (isDisposed) return@post
                    channel.invokeMethod(
                        "onError",
                        mapOf("message" to msg)
                    )
                }
            }
        }
    }

    private fun promptPassword(isRetry: Boolean) {
        mainHandler.post {
            channel.invokeMethod("onPasswordRequired", mapOf("retry" to isRetry), object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val password = result as? String
                    if (password != null) {
                        loadDocumentWithPassword(password, true)
                    } else {
                        // user cancelled
                        channel.invokeMethod(
                            "onError",
                            mapOf("message" to "This PDF is password protected")
                        )
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    channel.invokeMethod(
                        "onError",
                        mapOf("message" to "This PDF is password protected")
                    )
                }

                override fun notImplemented() {
                    channel.invokeMethod(
                        "onError",
                        mapOf("message" to "This PDF is password protected")
                    )
                }
            })
        }
    }

    /** Extracts and caches text for every page so subsequent searches are instant. */
    private fun startTextExtraction() {
        executor.execute {
            try {
                PDDocument.load(File(path), currentPassword).use { doc ->
                    val stripper = PDFTextStripper()
                    for (i in 1..doc.numberOfPages) {
                        stripper.startPage = i
                        stripper.endPage = i
                        pageTextCache[i] = stripper.getText(doc)
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun renderPages() {
        pagesContainer.removeAllViews()
        val renderer = renderer ?: return
        if (singlePage) {
            pagesContainer.addView(createPageView(initialPage.coerceIn(1, pageCount)))
        } else {
            for (pageIndex in 0 until pageCount) {
                pagesContainer.addView(createPageView(pageIndex + 1))
            }
        }
        applyZoom(preserveScrollPosition = false)
        root.post { extractBookmarks() }
    }

    private fun createPageView(pageNumber: Int): ImageView {
        val imageView = ImageView(context)
        imageView.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 0, 0, 24)
        }
        imageView.adjustViewBounds = true
        imageView.scaleType = ImageView.ScaleType.FIT_XY
        applyImageTheme(imageView)

        pageImageViews[pageNumber] = imageView

        try {
            executor.execute {
                val bitmap = renderPage(pageNumber - 1)
                mainHandler.post {
                    if (isDisposed) return@post
                    originalBitmaps[pageNumber] = bitmap
                    imageView.tag = PageSize(bitmap.width, bitmap.height)
                    if (singlePage) {
                        pagesContainer.removeAllViews()
                        pagesContainer.addView(imageView)
                    }
                    imageView.setImageBitmap(bitmap)
                    applyImageTheme(imageView)
                    updatePageLayout(imageView)
                    // Apply highlight if a search result is waiting for this page to render.
                    if (currentSearchText.isNotEmpty() &&
                        currentSearchMatchIndex > 0 &&
                        searchMatches.getOrNull(currentSearchMatchIndex - 1)?.pageNumber == pageNumber
                    ) {
                        applyHighlights(pageNumber, currentSearchText)
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // View was disposed concurrently and the executor already shut down; nothing to render.
        }
        return imageView
    }

    private fun renderPage(index: Int): Bitmap {
        synchronized(pdfiumLock) {
            val page = renderer?.openPage(index) ?: throw IllegalStateException("Renderer not ready")
            val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            page.close()
            return bitmap
        }
    }

    // ── Highlight helpers ─────────────────────────────────────────────────────

    /** Draws highlight rectangles for [searchText] on [pageNumber]'s bitmap, highlighting the active match in orange. Uses pre-calculated coordinates. */
    private fun applyHighlights(pageNumber: Int, searchText: String) {
        val imageView = pageImageViews[pageNumber] ?: return
        val original = originalBitmaps[pageNumber] ?: return
        highlightExecutor.execute {
            val pageMatches = searchMatches.filter { it.pageNumber == pageNumber }
            if (pageMatches.isEmpty()) return@execute
            
            val currentMatch = if (currentSearchMatchIndex > 0 && currentSearchMatchIndex <= searchMatches.size) {
                searchMatches[currentSearchMatchIndex - 1]
            } else null
            
            val highlighted = original.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = Canvas(highlighted)
            
            val normalPaint = Paint().apply {
                color = Color.argb(76, 255, 210, 0) // Yellow alpha 0.3
                style = Paint.Style.FILL
            }
            val activePaint = Paint().apply {
                color = Color.argb(140, 255, 128, 0) // Orange alpha 0.55
                style = Paint.Style.FILL
            }
            
            for (match in pageMatches) {
                val isCurrent = (currentMatch != null && currentMatch.pageNumber == pageNumber && currentMatch.rectIndex == match.rectIndex)
                val paint = if (isCurrent) activePaint else normalPaint
                val rect = match.rect
                canvas.drawRect(
                    rect.left * highlighted.width,
                    rect.top * highlighted.height,
                    rect.right * highlighted.width,
                    rect.bottom * highlighted.height,
                    paint
                )
            }
            mainHandler.post { imageView.setImageBitmap(highlighted) }
        }
    }

    /** Returns the original (un-highlighted) bitmap for [pageNumber]. Must be called on main thread. */
    private fun restorePageHighlight(pageNumber: Int) {
        val imageView = pageImageViews[pageNumber] ?: return
        val original = originalBitmaps[pageNumber] ?: return
        imageView.setImageBitmap(original)
    }

    // ── Zoom ──────────────────────────────────────────────────────────────────

    private fun applyZoom(preserveScrollPosition: Boolean = true, anchorX: Float? = null, anchorY: Float? = null) {
        val previousZoom = lastAppliedZoom.takeIf { it > 0f } ?: zoom
        val currentScrollX = horizontalScroll.scrollX
        val currentScrollY = verticalScroll.scrollY
        val viewportWidth = horizontalScroll.width
        val viewportHeight = verticalScroll.height
        val focusX = anchorX ?: (viewportWidth / 2f)
        val focusY = anchorY ?: (viewportHeight / 2f)

        for (index in 0 until pagesContainer.childCount) {
            (pagesContainer.getChildAt(index) as? ImageView)?.let { updatePageLayout(it) }
        }

        pagesContainer.requestLayout()

        if (preserveScrollPosition) {
            root.post {
                val contentFocusY = (currentScrollY + focusY) / previousZoom
                val targetScrollY = (contentFocusY * zoom - focusY).roundToInt().coerceAtLeast(0)
                val contentFocusX = (currentScrollX + focusX) / previousZoom
                val targetScrollX = (contentFocusX * zoom - focusX).roundToInt().coerceAtLeast(0)

                verticalScroll.scrollTo(0, targetScrollY)
                horizontalScroll.scrollTo(targetScrollX, 0)
            }
        }

        lastAppliedZoom = zoom
        channel.invokeMethod("onZoomChanged", zoom.toDouble())
    }

    private fun updatePageLayout(imageView: ImageView) {
        val pageSize = imageView.tag as? PageSize ?: return
        val layoutParams = (imageView.layoutParams as? LinearLayout.LayoutParams)
            ?: LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        val viewportWidth = horizontalScroll.width.takeIf { it > 0 } ?: root.width
        val viewportHeight = verticalScroll.height.takeIf { it > 0 } ?: root.height
        val aspectRatio = pageSize.width.toFloat() / pageSize.height.toFloat()

        if (vertical) {
            val baseWidth = viewportWidth.takeIf { it > 0 } ?: pageSize.width
            val width = (baseWidth * zoom).roundToInt().coerceAtLeast(1)
            val height = (width / aspectRatio).roundToInt().coerceAtLeast(1)
            layoutParams.width = width
            layoutParams.height = height
        } else {
            val baseHeight = viewportHeight.takeIf { it > 0 } ?: pageSize.height
            val height = (baseHeight * zoom).roundToInt().coerceAtLeast(1)
            val width = (height * aspectRatio).roundToInt().coerceAtLeast(1)
            layoutParams.width = width
            layoutParams.height = height
        }

        layoutParams.setMargins(0, 0, 0, 24)
        imageView.layoutParams = layoutParams
    }

    // ── Theme ─────────────────────────────────────────────────────────────────

    private fun applyTheme() {
        val backgroundColor = if (darkMode) Color.parseColor("#0F172A") else Color.WHITE
        root.setBackgroundColor(backgroundColor)
        verticalScroll.setBackgroundColor(backgroundColor)
        horizontalScroll.setBackgroundColor(backgroundColor)
        pagesContainer.setBackgroundColor(backgroundColor)
        for (index in 0 until pagesContainer.childCount) {
            (pagesContainer.getChildAt(index) as? ImageView)?.let { applyImageTheme(it) }
        }
    }

    private fun applyImageTheme(imageView: ImageView) {
        if (darkMode) {
            val matrix = ColorMatrix(
                floatArrayOf(
                    -1f, 0f, 0f, 0f, 255f,
                    0f, -1f, 0f, 0f, 255f,
                    0f, 0f, -1f, 0f, 255f,
                    0f, 0f, 0f, 1f, 0f
                )
            )
            imageView.colorFilter = ColorMatrixColorFilter(matrix)
            imageView.setBackgroundColor(Color.parseColor("#0F172A"))
        } else {
            imageView.colorFilter = null
            imageView.setBackgroundColor(Color.WHITE)
        }
    }

    // ── Channel callbacks ─────────────────────────────────────────────────────

    private fun sendReady() {
        channel.invokeMethod("onReady", null)
    }

    private fun sendPageChanged() {
        channel.invokeMethod(
            "onPageChanged",
            mapOf("pageNumber" to currentPage, "pageCount" to pageCount)
        )
    }

    private fun extractBookmarks() {
        executor.execute {
            val bookmarks = mutableListOf<Map<String, Any?>>()
            try {
                PDDocument.load(File(path), currentPassword).use { doc ->
                    // Build COSDictionary → 1-based page number map once.
                    // COSDictionary identity is the only reliable comparison in PDFBox Android.
                    val pageIndexMap = HashMap<COSDictionary, Int>()
                    val pages = doc.pages
                    for (i in 0 until pages.count) {
                        try { pageIndexMap[pages[i].cosObject] = i + 1 } catch (_: Exception) {}
                    }
                    val outline = doc.documentCatalog.documentOutline
                    if (outline != null) {
                        flattenOutline(outline.firstChild, doc, pageIndexMap, bookmarks)
                    }
                }
            } catch (_: Exception) {}
            mainHandler.post {
                channel.invokeMethod("onBookmarks", bookmarks)
            }
        }
    }

    private fun flattenOutline(
        item: PDOutlineItem?,
        doc: PDDocument,
        pageIndexMap: Map<COSDictionary, Int>,
        result: MutableList<Map<String, Any?>>
    ) {
        var current = item
        while (current != null) {
            // Capture next sibling BEFORE recursing so a child-level exception can't break iteration.
            val next = try { current.nextSibling } catch (_: Exception) { null }
            try {
                val title = current.title ?: ""
                val pageNumber = resolveOutlinePageNumber(current, doc, pageIndexMap)
                result.add(mapOf("title" to title, "pageNumber" to pageNumber))
                if (current.hasChildren()) {
                    flattenOutline(current.firstChild, doc, pageIndexMap, result)
                }
            } catch (_: Exception) {}
            current = next
        }
    }

    private fun resolveOutlinePageNumber(
        item: PDOutlineItem,
        doc: PDDocument,
        pageIndexMap: Map<COSDictionary, Int>
    ): Int {
        try {
            val fromDest = resolveDestPageNumber(item.destination, doc, pageIndexMap)
            if (fromDest > 0) return fromDest
            val action = item.action
            if (action is PDActionGoTo) {
                val fromAction = resolveDestPageNumber(action.destination, doc, pageIndexMap)
                if (fromAction > 0) return fromAction
            }
        } catch (_: Exception) {}
        return 1
    }

    private fun resolveDestPageNumber(
        dest: Any?,
        doc: PDDocument,
        pageIndexMap: Map<COSDictionary, Int>
    ): Int {
        when (dest) {
            is PDPageDestination -> {
                // Primary: match via COSDictionary key (avoids object-identity mismatch).
                try {
                    val cosPage = dest.page?.cosObject
                    if (cosPage != null) {
                        val idx = pageIndexMap[cosPage]
                        if (idx != null) return idx
                    }
                } catch (_: Exception) {}
                // Fallback: inline 0-based index stored in the destination array.
                try {
                    val idx = dest.retrievePageNumber()
                    if (idx >= 0) return idx + 1
                } catch (_: Exception) {}
            }
            is PDNamedDestination -> {
                // Named destinations are resolved via the document's name tree.
                try {
                    val resolved = doc.documentCatalog.names?.dests
                        ?.getValue(dest.namedDestination)
                    if (resolved is PDPageDestination) {
                        return resolveDestPageNumber(resolved, doc, pageIndexMap)
                    }
                } catch (_: Exception) {}
            }
        }
        return -1
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    private fun jumpToPageInternal(pageNumber: Int) {
        currentPage = pageNumber.coerceIn(1, pageCount.coerceAtLeast(1))
        val targetView = pagesContainer.getChildAt(currentPage - 1) ?: return
        root.post {
            if (vertical) {
                verticalScroll.scrollTo(0, targetView.top)
            } else {
                horizontalScroll.scrollTo(targetView.left, 0)
            }
            sendPageChanged()
        }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    private fun performSearch(text: String) {
        executor.execute {
            val matches = findAllMatches(text)
            mainHandler.post {
                val prevMatches = searchMatches
                searchMatches = matches
                currentSearchText = text
                currentSearchMatchIndex = if (matches.isNotEmpty()) 1 else 0
                
                // Clear any existing highlights before applying new ones.
                val pagesToClear = prevMatches.map { it.pageNumber }.distinct()
                for (page in pagesToClear) restorePageHighlight(page)
                
                if (matches.isNotEmpty()) {
                    val firstMatch = matches[0]
                    jumpToPageInternal(firstMatch.pageNumber)
                    applyHighlights(firstMatch.pageNumber, text)
                }
                channel.invokeMethod(
                    "onSearchChanged",
                    mapOf("text" to text, "count" to matches.size, "index" to currentSearchMatchIndex)
                )
            }
        }
    }

    private fun findAllMatches(searchText: String): List<SearchMatch> {
        val matches = mutableListOf<SearchMatch>()
        try {
            PDDocument.load(File(path), currentPassword).use { doc ->
                val lowerSearch = searchText.lowercase()
                val stripper = object : PDFTextStripper() {
                    val allPositions = mutableListOf<TextPosition>()
                    @Throws(java.io.IOException::class)
                    override fun writeString(text: String, textPositions: MutableList<TextPosition>) {
                        allPositions.addAll(textPositions)
                        super.writeString(text, textPositions)
                    }
                    
                    fun extractPageData(pageIndex: Int): Pair<String, List<TextPosition>> {
                        allPositions.clear()
                        startPage = pageIndex + 1
                        endPage = pageIndex + 1
                        val textStr = try {
                            getText(doc)
                        } catch (_: Exception) {
                            ""
                        }
                        return Pair(textStr, ArrayList(allPositions))
                    }
                }

                for (pageIndex in 0 until pageCount) {
                    val pageNum = pageIndex + 1
                    var pageText = pageTextCache[pageNum]
                    if (pageText == null || !pageText.contains(searchText, ignoreCase = true)) {
                        if (pageText != null) continue
                    }

                    val (textStr, posList) = stripper.extractPageData(pageIndex)
                    pageTextCache[pageNum] = textStr
                    
                    if (!textStr.contains(searchText, ignoreCase = true)) continue

                    val page = doc.getPage(pageIndex)
                    val pageWidth = page.mediaBox.width
                    val pageHeight = page.mediaBox.height

                    val posMap = mutableListOf<TextPosition>()
                    val fullText = StringBuilder()
                    for (tp in posList) {
                        val uni = tp.unicode ?: continue
                        for (ch in uni) {
                            posMap.add(tp)
                            fullText.append(ch)
                        }
                    }

                    val lower = fullText.toString().lowercase()
                    var idx = 0
                    var rectIdx = 0
                    while (true) {
                        val start = lower.indexOf(lowerSearch, idx)
                        if (start < 0) break
                        val end = (start + lowerSearch.length).coerceAtMost(posMap.size)
                        val matched = posMap.subList(start, end)
                        if (matched.isNotEmpty()) {
                            val minX = matched.minOf { it.x }
                            val maxX = matched.maxOf { it.x + it.width }
                            val minY = matched.minOf { it.y - it.height }
                            val maxY = matched.maxOf { it.y }
                            val rect = NormalizedRect(
                                left = (minX / pageWidth).coerceIn(0f, 1f),
                                top = (minY / pageHeight).coerceIn(0f, 1f),
                                right = (maxX / pageWidth).coerceIn(0f, 1f),
                                bottom = (maxY / pageHeight).coerceIn(0f, 1f),
                            )
                            matches.add(SearchMatch(pageNum, rect, rectIdx))
                            rectIdx++
                        }
                        idx = start + 1
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return matches
    }

    private fun clearSearchInternal() {
        val pagesToClear = searchMatches.map { it.pageNumber }.distinct()
        searchMatches = emptyList()
        currentSearchMatchIndex = 0
        currentSearchText = ""
        for (page in pagesToClear) restorePageHighlight(page)
        channel.invokeMethod(
            "onSearchChanged",
            mapOf("text" to "", "count" to 0, "index" to 0)
        )
    }

    // ── Method channel handler ────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "jumpToPage" -> {
                jumpToPageInternal((call.argument<Int>("pageNumber") ?: 1))
                result.success(null)
            }
            "nextPage" -> {
                jumpToPageInternal(currentPage + 1)
                result.success(null)
            }
            "previousPage" -> {
                jumpToPageInternal(currentPage - 1)
                result.success(null)
            }
            "zoomIn" -> {
                zoom = (zoom + ((call.argument<Double>("step") ?: 0.25).toFloat())).coerceAtMost(4f)
                applyZoom()
                result.success(null)
            }
            "zoomOut" -> {
                zoom = (zoom - ((call.argument<Double>("step") ?: 0.25).toFloat())).coerceAtLeast(0.5f)
                applyZoom()
                result.success(null)
            }
            "resetZoom" -> {
                zoom = 1f
                applyZoom()
                result.success(null)
            }
            "search" -> {
                val text = call.argument<String>("text") ?: ""
                if (text.isNotEmpty()) {
                    performSearch(text)
                } else {
                    clearSearchInternal()
                }
                result.success(null)
            }
            "clearSearch" -> {
                clearSearchInternal()
                result.success(null)
            }
            "requestBookmarks" -> {
                extractBookmarks()
                result.success(null)
            }
            "nextSearchResult" -> {
                if (searchMatches.isNotEmpty()) {
                    val prevPage = searchMatches[currentSearchMatchIndex - 1].pageNumber
                    currentSearchMatchIndex = (currentSearchMatchIndex % searchMatches.size) + 1
                    val newMatch = searchMatches[currentSearchMatchIndex - 1]
                    val newPage = newMatch.pageNumber
                    
                    if (prevPage != newPage) {
                        restorePageHighlight(prevPage)
                    }
                    
                    jumpToPageInternal(newPage)
                    applyHighlights(newPage, currentSearchText)
                    channel.invokeMethod(
                        "onSearchChanged",
                        mapOf(
                            "text" to currentSearchText,
                            "count" to searchMatches.size,
                            "index" to currentSearchMatchIndex
                        )
                    )
                }
                result.success(null)
            }
            "previousSearchResult" -> {
                if (searchMatches.isNotEmpty()) {
                    val prevPage = searchMatches[currentSearchMatchIndex - 1].pageNumber
                    currentSearchMatchIndex -= 1
                    if (currentSearchMatchIndex < 1) currentSearchMatchIndex = searchMatches.size
                    val newMatch = searchMatches[currentSearchMatchIndex - 1]
                    val newPage = newMatch.pageNumber
                    
                    if (prevPage != newPage) {
                        restorePageHighlight(prevPage)
                    }
                    
                    jumpToPageInternal(newPage)
                    applyHighlights(newPage, currentSearchText)
                    channel.invokeMethod(
                        "onSearchChanged",
                        mapOf(
                            "text" to currentSearchText,
                            "count" to searchMatches.size,
                            "index" to currentSearchMatchIndex
                        )
                    )
                }
                result.success(null)
            }
            "getPageThumbnail" -> {
                val pageNumber = call.argument<Int>("pageNumber") ?: 1
                val width = call.argument<Int>("width") ?: 200
                executor.execute {
                    val renderer = renderer
                    if (renderer == null || pageNumber < 1 || pageNumber > pageCount) {
                        mainHandler.post { result.success(null) }
                        return@execute
                    }
                    try {
                        val bitmap = synchronized(pdfiumLock) {
                            val page = renderer.openPage(pageNumber - 1)
                            val ratio = page.height.toFloat() / page.width.toFloat()
                            val targetHeight = (width * ratio).roundToInt().coerceAtLeast(1)
                            val bmp = Bitmap.createBitmap(width, targetHeight, Bitmap.Config.ARGB_8888)
                            bmp.eraseColor(Color.WHITE)
                            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            page.close()
                            bmp
                        }
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
                        val bytes = stream.toByteArray()
                        mainHandler.post { result.success(bytes) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(null) }
                    }
                }
            }
            "openBookmarks" -> result.success(null)
            "setDarkMode" -> {
                darkMode = call.argument<Boolean>("enabled") ?: false
                mainHandler.post { applyTheme() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        isDisposed = true
        mainHandler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        synchronized(pdfiumLock) {
            renderer?.close()
        }
        fileDescriptor?.close()
        executor.shutdownNow()
        highlightExecutor.shutdownNow()
        decryptedFile?.delete()
    }

    companion object {
        // android.graphics.pdf.PdfRenderer wraps pdfium, which keeps process-wide global
        // module state (e.g. CPDF_PageModule's stock color spaces). Each PdfNativeView runs
        // its own single-thread executor, so when multiple instances exist at once (e.g.
        // while swapping demo sources) their PdfRenderer/Page calls can interleave across
        // threads and corrupt that shared state, crashing natively in libpdfium. Serialize
        // all PdfRenderer creation/open/render/close calls across every instance.
        private val pdfiumLock = Any()
    }
}

private data class PageSize(val width: Int, val height: Int)
private data class NormalizedRect(val left: Float, val top: Float, val right: Float, val bottom: Float)
private data class SearchMatch(val pageNumber: Int, val rect: NormalizedRect, val rectIndex: Int)
