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
    private val verticalScroll = object : ScrollView(context) {
        override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
            super.onScrollChanged(l, t, oldl, oldt)
            updateCurrentPageFromScroll()
        }
    }
    private val horizontalScroll = object : HorizontalScrollView(context) {
        override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
            super.onScrollChanged(l, t, oldl, oldt)
            updateCurrentPageFromScroll()
        }
    }
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
    private var previousPage = 1
    private var zoom = ((creationParams?.get("initialZoomLevel") as? Number)?.toFloat() ?: 1f).coerceAtLeast(1f)
    private var lastAppliedZoom = zoom
    private var pinchFocusX = 0f
    private var pinchFocusY = 0f
    // Latched for the duration of a pinch (from the second finger touching down until
    // every finger lifts) so the underlying ScrollViews never treat the pinch centroid's
    // movement — or the residual motion as fingers lift — as a scroll/fling.
    private var isPinching = false
    private val singlePage = creationParams?.get("singlePage") as? Boolean ?: false
    private val vertical = (creationParams?.get("scrollDirection") as? String ?: "vertical") == "vertical"
    private val path = creationParams?.get("path") as String
    private var currentPassword = creationParams?.get("password") as? String ?: ""
    private var initialPage = (creationParams?.get("initialPage") as? Number)?.toInt() ?: 1
    private var darkMode = creationParams?.get("darkMode") as? Boolean ?: false
    private val separatorThickness = (context.resources.displayMetrics.density + 0.5f).toInt()
    private var searchMatches = listOf<SearchMatch>()
    private var currentSearchMatchIndex = 0
    private var currentSearchText = ""
    private var suppressPageUpdates = false
    private var pinchAnchorX = 0f
    private var pinchAnchorY = 0f

    // Keyed by page number (1-based). Populated on executor; read on executor (single-thread, no races).
    private val pageTextCache = mutableMapOf<Int, String>()
    // Accessed from both main thread and executor, so use concurrent map.
    private val pageImageViews = ConcurrentHashMap<Int, ImageView>()
    private val originalBitmaps = ConcurrentHashMap<Int, Bitmap>()

    init {
        PDFBoxResourceLoader.init(context)
        channel.setMethodCallHandler(this)
        pagesContainer.orientation = LinearLayout.VERTICAL
        pagesContainer.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )

        verticalScroll.isFillViewport = true
        horizontalScroll.isFillViewport = true

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
                applyZoom()
                return true
            }
        })
        scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                suppressPageUpdates = true
                pinchAnchorX = detector.focusX
                pinchAnchorY = detector.focusY
                return true
            }

            override fun onScale(detector: ScaleGestureDetector): Boolean {
                if (detector.scaleFactor == 1f) return false
                zoom = (zoom * detector.scaleFactor).coerceIn(1f, 4f)
                applyZoom()
                return true
            }

            override fun onScaleEnd(detector: ScaleGestureDetector) {
                suppressPageUpdates = false
                updateCurrentPageFromScroll()
            }
        })

        val touchListener = View.OnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_POINTER_DOWN || event.pointerCount > 1) {
                isPinching = true
                verticalScroll.requestDisallowInterceptTouchEvent(true)
                horizontalScroll.requestDisallowInterceptTouchEvent(true)
            }

            scaleGestureDetector.onTouchEvent(event)
            if (!isPinching) {
                gestureDetector.onTouchEvent(event)
            }

            val consumed = isPinching

            when (event.actionMasked) {
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> isPinching = false
            }

            consumed
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
                if (pageIndex < pageCount - 1) {
                    pagesContainer.addView(createSeparatorView())
                }
            }
        }
        root.post { extractBookmarks() }
    }

    private fun createPageView(pageNumber: Int): ImageView {
        val imageView = ImageView(context)
        imageView.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
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

    private fun createSeparatorView(): View {
        val separator = View(context)
        separator.setBackgroundColor(
            if (darkMode) Color.parseColor("#334155") else Color.parseColor("#E5E7EB")
        )
        val gap = scaledSeparatorGap()
        separator.layoutParams = LinearLayout.LayoutParams(
            if (vertical) ViewGroup.LayoutParams.MATCH_PARENT else separatorThickness,
            if (vertical) separatorThickness else ViewGroup.LayoutParams.MATCH_PARENT
        ).apply {
            if (vertical) {
                topMargin = gap
                bottomMargin = gap
            } else {
                leftMargin = gap
                rightMargin = gap
            }
        }
        return separator
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

    private fun scaledPageGap(): Int = (24f * zoom).roundToInt().coerceAtLeast(0)
    private fun scaledSeparatorGap(): Int = (12f * zoom).roundToInt().coerceAtLeast(0)

    private fun applyZoom() {
        lastAppliedZoom = zoom

        for ((pageNum, imageView) in pageImageViews) {
            // Only zoom current page, others stay at zoom 1.0
            val pageZoom = if (pageNum == currentPage) zoom else 1f
            updatePageLayout(imageView, pageZoom)
        }

        channel.invokeMethod("onZoomChanged", zoom.toDouble())
    }

    private fun updatePageLayout(imageView: ImageView, pageZoom: Float = 1f) {
        val pageSize = imageView.tag as? PageSize ?: return
        val layoutParams = (imageView.layoutParams as? LinearLayout.LayoutParams)
            ?: LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        val viewportWidth = horizontalScroll.width.takeIf { it > 0 } ?: root.width
        val aspectRatio = pageSize.width.toFloat() / pageSize.height.toFloat()

        val baseWidth = (viewportWidth.toFloat() - 32f).coerceAtLeast(1f)
        val width = (baseWidth * pageZoom).toInt().coerceAtLeast(1)
        val height = (width / aspectRatio).toInt().coerceAtLeast(1)
        layoutParams.width = width
        layoutParams.height = height

        val gap = (24f * pageZoom).roundToInt().coerceAtLeast(0)
        layoutParams.setMargins(0, 0, 0, gap)
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
        val childIndex = if (singlePage) {
            0
        } else {
            (currentPage - 1) * 2
        }
        val targetView = pagesContainer.getChildAt(childIndex) ?: return
        root.post {
            verticalScroll.scrollTo(0, targetView.top)
            sendPageChanged()
        }
    }

    private fun updateCurrentPageFromScroll() {
        if (pageCount <= 0 || suppressPageUpdates) return

        val scrollY = verticalScroll.scrollY
        val viewHeight = verticalScroll.height
        val midY = scrollY + viewHeight / 2
        var closest = currentPage
        var minDist = Double.MAX_VALUE

        for ((pageNumber, imageView) in pageImageViews) {
            if (!imageView.isShown) continue

            val pageTop = imageView.top
            val pageBottom = imageView.bottom

            // Check if page is visible in viewport
            val isInView = pageTop < (scrollY + viewHeight) && pageBottom > scrollY
            if (!isInView) continue

            val center = pageTop + imageView.height / 2
            val dist = kotlin.math.abs(center - midY).toDouble()
            if (dist < minDist) {
                minDist = dist
                closest = pageNumber
            }
        }

        if (closest != currentPage) {
            // Reset zoom when changing pages
            if (zoom != 1f) {
                previousPage = currentPage
                zoom = 1f
                applyZoom()
            }
            currentPage = closest
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
                zoom = (zoom - ((call.argument<Double>("step") ?: 0.25).toFloat())).coerceAtLeast(1f)
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
