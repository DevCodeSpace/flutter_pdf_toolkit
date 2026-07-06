import Flutter
import PDFKit
import UIKit
import CoreImage

final class PdfNativeView: NSObject, FlutterPlatformView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
  private let channel: FlutterMethodChannel
  private var document: PDFDocument?
  private let container = UIView()
  private let scrollView = UIScrollView()
  private let pagesContainer = UIView()

  private var pageViews: [Int: UIImageView] = [:]
  private var originalImages: [Int: UIImage] = [:]
  private var invertedImages: [Int: UIImage] = [:]  // pre-cached for instant toggle

  private var pageCount: Int = 0
  private var currentPage: Int = 1
  private var previousPage: Int = 1
  private var zoom: CGFloat
  private var suppressPageUpdates = false
  private var pinchStartZoom: CGFloat = 1.0
  private let path: String
  private let password: String?
  private let initialPage: Int
  private let singlePage: Bool
  private let vertical: Bool
  private var darkMode: Bool

  private var searchMatches: [PDFSelection] = []
  private var currentMatchIndex: Int = 0
  private var currentSearchText: String = ""
  private var highlightedPages: [Int: (original: UIImage, inverted: UIImage)] = [:]

  private let renderQueue = DispatchQueue(label: "pdf.render", qos: .userInitiated)
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let pageSpacing: CGFloat = 16

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    creationParams: [String: Any]?
  ) {
    self.channel = FlutterMethodChannel(
      name: "flutter_pdf_toolkit_view_\(viewId)",
      binaryMessenger: messenger
    )
    self.path = creationParams?["path"] as? String ?? ""
    self.password = creationParams?["password"] as? String
    self.initialPage = creationParams?["initialPage"] as? Int ?? 1
    self.singlePage = creationParams?["singlePage"] as? Bool ?? false
    self.vertical = (creationParams?["scrollDirection"] as? String ?? "vertical") == "vertical"
    self.darkMode = creationParams?["darkMode"] as? Bool ?? false
    self.zoom = max(CGFloat((creationParams?["initialZoomLevel"] as? Double) ?? 1.0), 1.0)
    super.init()
    channel.setMethodCallHandler(handleMethodCall(_:result:))
    setupScrollView()
    loadDocument()
  }

  func view() -> UIView { container }

  // MARK: - Setup

  private func setupScrollView() {
    scrollView.delegate = self
    scrollView.showsVerticalScrollIndicator = true
    scrollView.showsHorizontalScrollIndicator = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.isScrollEnabled = true
    scrollView.canCancelContentTouches = false

    container.addSubview(scrollView)
    scrollView.addSubview(pagesContainer)

    let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
    doubleTapGesture.numberOfTapsRequired = 2
    doubleTapGesture.delegate = self
    container.addGestureRecognizer(doubleTapGesture)

    let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    pinchGesture.delegate = self
    container.addGestureRecognizer(pinchGesture)

    // Keep scroll gestures, but disable the native pinch-to-zoom path so only the current page
    // is resized through our manual layout updates.
    scrollView.pinchGestureRecognizer?.isEnabled = false

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    applyThemeColors()
  }

  // MARK: - UIScrollViewDelegate

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !suppressPageUpdates else { return }
    updateCurrentPageFromScroll()
  }

  private func applyZoom() {
    let wasSuppressing = suppressPageUpdates
    suppressPageUpdates = true
    updatePageFramesForZoom()
    centerPagesIfNeeded()
    suppressPageUpdates = wasSuppressing
    channel.invokeMethod("onZoomChanged", arguments: Double(zoom))
  }

  @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
    zoom = zoom > 1.5 ? 1.0 : min(zoom * 2, 4.0)
    applyZoom()
  }

  @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .began:
      suppressPageUpdates = true
      pinchStartZoom = zoom
    case .changed:
      zoom = max(1.0, min(pinchStartZoom * gesture.scale, 4.0))
      applyZoom()
    case .ended, .cancelled, .failed:
      suppressPageUpdates = false
      updateCurrentPageFromScroll()
    default:
      break
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    true
  }

  private func centerPagesIfNeeded() {
    let boundsSize = scrollView.bounds.size
    let contentSize = scrollView.contentSize
    let hInset = max((boundsSize.width - contentSize.width) / 2, 0)
    let vInset = max((boundsSize.height - contentSize.height) / 2, 0)
    scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset, bottom: vInset, right: hInset)
  }

  private func updateCurrentPageFromScroll() {
    let midY = scrollView.contentOffset.y + scrollView.bounds.height / 2
    let midX = scrollView.contentOffset.x + scrollView.bounds.width / 2
    var closest = currentPage
    var minDist = CGFloat.greatestFiniteMagnitude

    for (pageNum, iv) in pageViews {
      let pageRect = iv.frame

      if vertical {
        let isPageInView = pageRect.minY < (scrollView.contentOffset.y + scrollView.bounds.height) &&
                          pageRect.maxY > scrollView.contentOffset.y
        if isPageInView {
          let dist = abs(pageRect.midY - midY)
          if dist < minDist { minDist = dist; closest = pageNum }
        }
      } else {
        let isPageInView = pageRect.minX < (scrollView.contentOffset.x + scrollView.bounds.width) &&
                          pageRect.maxX > scrollView.contentOffset.x
        if isPageInView {
          let dist = abs(pageRect.midX - midX)
          if dist < minDist { minDist = dist; closest = pageNum }
        }
      }
    }

    if closest != currentPage {
      // Reset zoom when changing pages
      if zoom != 1.0 {
        previousPage = currentPage
        zoom = 1.0
        applyZoom()
      }
      currentPage = closest
      sendPageChanged()
    }
  }

  // MARK: - Document Loading

  private func loadDocument() {
    renderQueue.async { [weak self] in
      guard let self else { return }
      let url = URL(fileURLWithPath: self.path)
      guard let doc = PDFDocument(url: url) else {
        DispatchQueue.main.async {
          self.channel.invokeMethod("onError", arguments: ["message": "Unable to open PDF"])
        }
        return
      }
      if doc.isLocked {
        let pwd = self.password ?? ""
        if !pwd.isEmpty && doc.unlock(withPassword: pwd) {
          self.onDocumentLoaded(doc)
        } else {
          self.unlockDocument(doc, isRetry: !pwd.isEmpty)
        }
      } else {
        self.onDocumentLoaded(doc)
      }
    }
  }

  private func unlockDocument(_ doc: PDFDocument, isRetry: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.channel.invokeMethod("onPasswordRequired", arguments: ["retry": isRetry]) { [weak self] result in
        guard let self = self else { return }
        if let password = result as? String {
          self.renderQueue.async { [weak self] in
            guard let self = self else { return }
            let unlocked = doc.unlock(withPassword: password)
            if unlocked {
              self.onDocumentLoaded(doc)
            } else {
              self.unlockDocument(doc, isRetry: true)
            }
          }
        } else {
          DispatchQueue.main.async {
            self.channel.invokeMethod("onError", arguments: ["message": "This PDF is password protected"])
          }
        }
      }
    }
  }

  private func onDocumentLoaded(_ doc: PDFDocument) {
    self.document = doc
    self.pageCount = doc.pageCount
    DispatchQueue.main.async {
      self.layoutPages()
      self.currentPage = self.initialPage.clamped(1, self.pageCount)
      self.applyZoom()
      self.sendBookmarks()
      self.channel.invokeMethod("onReady", arguments: nil)
      self.jumpToPageInternal(self.initialPage, animated: false)
    }
  }

  // MARK: - Page Layout

  private func layoutPages() {
    pagesContainer.subviews.forEach { $0.removeFromSuperview() }
    pageViews.removeAll()
    originalImages.removeAll()
    invertedImages.removeAll()
    guard let document, pageCount > 0 else { return }

    let viewportW = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
    let pagesToShow = singlePage ? [initialPage.clamped(1, pageCount)] : Array(1...pageCount)
    let separatorThickness = 1.0 / UIScreen.main.scale

    var offset: CGFloat = pageSpacing
    var maxWidth: CGFloat = viewportW

    for pageNum in pagesToShow {
      guard let page = document.page(at: pageNum - 1) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      let ratio = bounds.width / bounds.height

      // Base layout; zoom is applied by resizing only the current page later.
      let w = viewportW - 32
      let h = w / ratio

      let frame: CGRect = CGRect(x: 16, y: offset, width: w, height: h)
      offset += h + pageSpacing

      let iv = UIImageView(frame: frame)
      iv.contentMode = .scaleAspectFit
      iv.backgroundColor = UIColor(hex: darkMode ? "#0F172A" : "#FFFFFF")
      pagesContainer.addSubview(iv)
      pageViews[pageNum] = iv

      if pageNum != pagesToShow.last {
        let separatorFrame = CGRect(
          x: 16,
          y: frame.maxY + (pageSpacing - separatorThickness) / 2,
          width: w,
          height: separatorThickness
        )
        let separator = UIView(frame: separatorFrame)
        separator.backgroundColor = UIColor.separator
        pagesContainer.addSubview(separator)
      }
    }

    let totalSize: CGSize = CGSize(width: viewportW, height: offset)
    pagesContainer.frame = CGRect(origin: .zero, size: totalSize)
    scrollView.contentSize = totalSize

    for pageNum in pagesToShow { renderPage(pageNum) }
  }

  private func updatePageFramesForZoom() {
    guard let document, pageCount > 0 else { return }

    let viewportW = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
    let pagesToShow = singlePage ? [initialPage.clamped(1, pageCount)] : Array(1...pageCount)
    let separatorThickness = 1.0 / UIScreen.main.scale

    var offset: CGFloat = pageSpacing
    var subviewIndex = 0
    var maxWidth: CGFloat = viewportW

    for pageNum in pagesToShow {
      guard let page = document.page(at: pageNum - 1) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      let ratio = bounds.width / bounds.height

      // Only zoom current page, others at base size
      let pageZoom = (pageNum == currentPage) ? zoom : 1.0
      let baseWidth = viewportW - 32
      let w = baseWidth * pageZoom
      let h = w / ratio
      maxWidth = max(maxWidth, w + 32)

      let frame: CGRect = CGRect(x: 16, y: offset, width: w, height: h)
      offset += h + pageSpacing

      if let iv = pagesContainer.subviews[safe: subviewIndex] as? UIImageView {
        iv.frame = frame
        pageViews[pageNum] = iv
      }
      subviewIndex += 1

      if pageNum != pagesToShow.last {
        let separatorFrame = CGRect(
          x: 16,
          y: frame.maxY + (pageSpacing - separatorThickness) / 2,
          width: w,
          height: separatorThickness
        )
        if let separator = pagesContainer.subviews[safe: subviewIndex] as? UIView, !(separator is UIImageView) {
          separator.frame = separatorFrame
        }
        subviewIndex += 1
      }
    }

    let totalSize: CGSize = CGSize(width: maxWidth, height: offset)
    pagesContainer.frame = CGRect(origin: .zero, size: totalSize)
    scrollView.contentSize = totalSize
  }

  // MARK: - Rendering

  private func renderPage(_ pageNumber: Int) {
    guard let document, let page = document.page(at: pageNumber - 1) else { return }
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = UIScreen.main.scale
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    let isDark = self.darkMode

    renderQueue.async { [weak self] in
      guard let self else { return }
      let renderer = UIGraphicsImageRenderer(size: size)
      let original = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.cgContext.translateBy(x: 0, y: size.height)
        ctx.cgContext.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: ctx.cgContext)
      }
      // Pre-cache both versions so theme toggle is instant (no async work needed later)
      let inverted = self.invertImage(original) ?? original

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.originalImages[pageNumber] = original
        self.invertedImages[pageNumber] = inverted
        self.pageViews[pageNumber]?.image = isDark ? inverted : original
        // Apply highlight if a search result is waiting for this page to render.
        if !self.currentSearchText.isEmpty,
           self.currentMatchIndex > 0,
           self.currentMatchIndex <= self.searchMatches.count,
           let matchPage = self.searchMatches[self.currentMatchIndex - 1].pages.first,
           let document = self.document,
           document.index(for: matchPage) + 1 == pageNumber {
          self.applyHighlights(on: pageNumber)
        }
      }
    }
  }

  private func invertImage(_ image: UIImage) -> UIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }
    guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    guard let output = filter.outputImage,
          let cgImage = ciContext.createCGImage(output, from: output.extent)
    else { return nil }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }

  // MARK: - Theme

  private func applyThemeColors() {
    let bg = UIColor(hex: darkMode ? "#0F172A" : "#FFFFFF")
    container.backgroundColor = bg
    scrollView.backgroundColor = bg
    pagesContainer.backgroundColor = bg
  }

  // Fully synchronous — uses pre-cached images, no async work, no glitch
  private func applyTheme() {
    applyThemeColors()
    for (pageNum, iv) in pageViews {
      iv.backgroundColor = UIColor(hex: darkMode ? "#0F172A" : "#FFFFFF")
      if let highlight = highlightedPages[pageNum] {
        iv.image = darkMode ? highlight.inverted : highlight.original
      } else if darkMode {
        iv.image = invertedImages[pageNum] ?? originalImages[pageNum]
      } else {
        iv.image = originalImages[pageNum]
      }
    }
  }

  // MARK: - Navigation

  private func jumpToPageInternal(_ pageNumber: Int, animated: Bool = true) {
    let clamped = pageNumber.clamped(1, max(1, pageCount))
    currentPage = clamped
    guard let iv = pageViews[clamped] else { sendPageChanged(); return }
    
    if vertical {
      scrollView.setContentOffset(CGPoint(x: 0, y: iv.frame.minY - pageSpacing), animated: animated)
    } else {
      scrollView.setContentOffset(CGPoint(x: iv.frame.minX - pageSpacing, y: 0), animated: animated)
    }
    sendPageChanged()
  }

  private func sendPageChanged() {
    channel.invokeMethod("onPageChanged", arguments: ["pageNumber": currentPage, "pageCount": pageCount])
  }

  // MARK: - Bookmarks

  private func sendBookmarks() {
    guard let document else {
      channel.invokeMethod("onBookmarks", arguments: [] as [[String: Any]])
      return
    }
    channel.invokeMethod("onBookmarks", arguments: flattenOutline(document.outlineRoot, document: document))
  }

  private func flattenOutline(_ node: PDFOutline?, document: PDFDocument) -> [[String: Any]] {
    guard let node else { return [] }
    var result: [[String: Any]] = []
    for i in 0..<node.numberOfChildren {
      guard let child = node.child(at: i) else { continue }
      let pageNum = child.destination.flatMap { dest -> Int? in
        guard let p = dest.page else { return nil }
        return document.index(for: p) + 1
      } ?? 1
      result.append(["title": child.label ?? "", "pageNumber": pageNum])
      result.append(contentsOf: flattenOutline(child, document: document))
    }
    return result
  }

  // MARK: - Search

  private func performSearch(_ text: String) {
    guard let document else { return }
    clearHighlights()
    searchMatches = document.findString(text, withOptions: .caseInsensitive) ?? []
    currentMatchIndex = searchMatches.isEmpty ? 0 : 1
    currentSearchText = text
    if let first = searchMatches.first, let page = first.pages.first {
      let pageNumber = document.index(for: page) + 1
      jumpToPageInternal(pageNumber, animated: true)
      applyHighlights(on: pageNumber)
    }
    sendSearchChanged()
  }

  private func clearSearch() {
    clearHighlights()
    searchMatches = []; currentMatchIndex = 0; currentSearchText = ""
    channel.invokeMethod("onSearchChanged", arguments: ["text": "", "count": 0, "index": 0])
  }

  private func sendSearchChanged() {
    channel.invokeMethod("onSearchChanged", arguments: [
      "text": currentSearchText,
      "count": searchMatches.count,
      "index": currentMatchIndex,
    ])
  }

  /// Draws highlight rectangles for every search match on [pageNumber] over the
  /// cached page images. The currently active/focused search match is drawn in orange, while
  /// other matches on the page are drawn in semi-transparent yellow.
  private func applyHighlights(on pageNumber: Int) {
    guard let document, let page = document.page(at: pageNumber - 1),
          let original = originalImages[pageNumber],
          let inverted = invertedImages[pageNumber]
    else { return }

    let matchesOnPage = searchMatches.filter { $0.pages.contains(page) }
    guard !matchesOnPage.isEmpty else { return }

    let currentSelection = (currentMatchIndex > 0 && currentMatchIndex <= searchMatches.count) ? searchMatches[currentMatchIndex - 1] : nil
    let pageBounds = page.bounds(for: .mediaBox)
    let isDark = darkMode

    renderQueue.async { [weak self] in
      guard let self else { return }

      func draw(on base: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { ctx in
          base.draw(at: .zero)

          let cgContext = ctx.cgContext
          let scaleX = base.size.width / pageBounds.width
          let scaleY = base.size.height / pageBounds.height

          for selection in matchesOnPage {
            let isCurrent = (selection == currentSelection)
            if isCurrent {
              cgContext.setFillColor(UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.55).cgColor) // Orange for current active match
            } else {
              cgContext.setFillColor(UIColor(red: 1.0, green: 0.8235, blue: 0.0, alpha: 0.3).cgColor) // Yellow for other matches
            }

            for line in selection.selectionsByLine() {
              let b = line.bounds(for: page)
              let rect = CGRect(
                x: (b.minX - pageBounds.minX) * scaleX,
                y: base.size.height - (b.maxY - pageBounds.minY) * scaleY,
                width: b.width * scaleX,
                height: b.height * scaleY
              )
              cgContext.fill(rect)
            }
          }
        }
      }

      let highlightedOriginal = draw(on: original)
      let highlightedInverted = draw(on: inverted)

      DispatchQueue.main.async {
        self.highlightedPages[pageNumber] = (highlightedOriginal, highlightedInverted)
        self.pageViews[pageNumber]?.image = isDark ? highlightedInverted : highlightedOriginal
      }
    }
  }

  /// Restores [pageNumber]'s image to its plain (non-highlighted) cached version.
  private func restoreHighlight(on pageNumber: Int) {
    guard highlightedPages.removeValue(forKey: pageNumber) != nil else { return }
    pageViews[pageNumber]?.image = darkMode ? invertedImages[pageNumber] : originalImages[pageNumber]
  }

  private func clearHighlights() {
    for pageNumber in Array(highlightedPages.keys) {
      restoreHighlight(on: pageNumber)
    }
  }

  // MARK: - Method Channel

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "jumpToPage":
      if let args = call.arguments as? [String: Any], let page = args["pageNumber"] as? Int {
        jumpToPageInternal(page)
      }
      result(nil)
    case "nextPage":
      jumpToPageInternal(currentPage + 1)
      result(nil)
    case "previousPage":
      jumpToPageInternal(currentPage - 1)
      result(nil)
    case "zoomIn":
      let step = CGFloat(((call.arguments as? [String: Any])?["step"] as? Double) ?? 0.25)
      zoom = min(zoom + step, 4.0)
      applyZoom()
      result(nil)
    case "zoomOut":
      let step = CGFloat(((call.arguments as? [String: Any])?["step"] as? Double) ?? 0.25)
      zoom = max(zoom - step, 1.0)
      applyZoom()
      result(nil)
    case "resetZoom":
      zoom = 1.0
      applyZoom()
      result(nil)
    case "search":
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      text.isEmpty ? clearSearch() : performSearch(text)
      result(nil)
    case "clearSearch":
      clearSearch()
      result(nil)
    case "requestBookmarks":
      sendBookmarks()
      result(nil)
    case "nextSearchResult":
      guard !searchMatches.isEmpty else { result(nil); return }
      let prevPage = document.flatMap { doc in
        searchMatches[currentMatchIndex - 1].pages.first.map { doc.index(for: $0) + 1 }
      } ?? 1
      currentMatchIndex = (currentMatchIndex % searchMatches.count) + 1
      if let page = searchMatches[currentMatchIndex - 1].pages.first, let document {
        let pageNumber = document.index(for: page) + 1
        jumpToPageInternal(pageNumber)
        if prevPage != pageNumber {
          restoreHighlight(on: prevPage)
        }
        applyHighlights(on: pageNumber)
      }
      sendSearchChanged()
      result(nil)
    case "previousSearchResult":
      guard !searchMatches.isEmpty else { result(nil); return }
      let prevPage = document.flatMap { doc in
        searchMatches[currentMatchIndex - 1].pages.first.map { doc.index(for: $0) + 1 }
      } ?? 1
      currentMatchIndex -= 1
      if currentMatchIndex < 1 { currentMatchIndex = searchMatches.count }
      if let page = searchMatches[currentMatchIndex - 1].pages.first, let document {
        let pageNumber = document.index(for: page) + 1
        jumpToPageInternal(pageNumber)
        if prevPage != pageNumber {
          restoreHighlight(on: prevPage)
        }
        applyHighlights(on: pageNumber)
      }
      sendSearchChanged()
      result(nil)
    case "getPageThumbnail":
      guard let args = call.arguments as? [String: Any],
        let pageNumber = args["pageNumber"] as? Int,
        let document,
        let page = document.page(at: pageNumber - 1)
      else {
        result(nil)
        return
      }
      let width = CGFloat((args["width"] as? NSNumber)?.doubleValue ?? 200)
      renderQueue.async {
        let bounds = page.bounds(for: .mediaBox)
        let ratio = bounds.height / max(bounds.width, 1)
        let size = CGSize(width: width, height: width * ratio)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        let data = thumbnail.pngData()
        DispatchQueue.main.async {
          if let data {
            result(FlutterStandardTypedData(bytes: data))
          } else {
            result(nil)
          }
        }
      }
    case "openBookmarks":
      result(nil)
    case "setDarkMode":
      if let args = call.arguments as? [String: Any] {
        darkMode = args["enabled"] as? Bool ?? false
        applyTheme()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

// MARK: - Helpers

private extension Int {
  func clamped(_ lo: Int, _ hi: Int) -> Int { self < lo ? lo : (self > hi ? hi : self) }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    index >= 0 && index < count ? self[index] : nil
  }
}

private extension UIColor {
  convenience init(hex: String) {
    let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var val: UInt64 = 0
    Scanner(string: h).scanHexInt64(&val)
    self.init(
      red: CGFloat((val >> 16) & 0xFF) / 255,
      green: CGFloat((val >> 8) & 0xFF) / 255,
      blue: CGFloat(val & 0xFF) / 255,
      alpha: 1
    )
  }
}
