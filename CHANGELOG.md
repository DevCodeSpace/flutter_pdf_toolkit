## 0.0.2

- **Network PDF Loading**: Normalize PDF sources, support Google Drive sharing URLs, and cache downloads for reuse.
- **Search Enhancements**: Add loading indicator, horizontal scrolling, "Searching..." text, and dimmed overlay during search.
- **Search State**: Track and cleanly reset search state in controller.
- **Zoom & Navigation**: Reset zoom to 1.0 on page changes. Improve page detection and preserve scroll during zoom.
- **Gestures**: Refine double-tap and pinch zoom on Android/iOS. Fix Android scroll/page updates during pinch.
- **Signature Pad**: Clamp drawing to canvas bounds and clip exported strokes correctly.
- **iOS Security**: Add NSAppTransportSecurity for Google Drive PDF downloads.
- **Network Improvements**: Better error handling, debug logging, Google Drive confirmation retry mechanism.
- **API Cleanup**: Simplify Dart API surface and widget implementations.
- **Tests & Docs**: Expand tests for URL normalization and caching.

## 0.0.1

- TODO: Describe initial release.
- Added natively-rendered page thumbnails: `controller.getPageThumbnail()`
  and a real thumbnail grid (replacing the placeholder "Page N" labels) on
  both Android and iOS.
- Added double-tap-to-zoom on iOS (toggles between default and 2x zoom,
  centered on the tap point), matching the existing Android behavior.
- Added `FlutterPdfPro.splitPdf()` to split a PDF into multiple files by
  page range, and `FlutterPdfPro.getPdfPageCount()` to read a PDF's page
  count, both implemented natively on Android (`pdfbox-android`) and iOS
  (`PDFKit`).
- Added PDF signing support: a new "Sign document" toolbar action
  (`showSignature`, `onSigned`) lets users draw a signature, position/resize
  it over the current page, and stamp it onto the document via the new
  `FlutterPdfPro.signPdf()` method (implemented natively with
  `pdfbox-android` on Android and `CoreGraphics` on iOS). Also exports a
  reusable `SignaturePad`/`SignaturePadController` for building custom
  signature-capture UIs.
- Added page reordering support: a new "Reorder pages" toolbar action
  (`showReorder`, `onPagesReordered`) lets users drag page thumbnails into a
  new order and save the rearranged PDF via the new
  `FlutterPdfPro.reorderPages()` method (implemented natively with
  `pdfbox-android` on Android and `PDFKit` on iOS).
- Added a built-in "Add pages" toolbar action (`showAddPages`,
  `onAddPagesRequested`, `onPagesAdded`) that lets users pick where to insert
  new pages from a page-thumbnail grid, then hands off to the host app to
  supply one or more PDF/image file paths to insert. Backed by two new
  static methods: `FlutterPdfPro.imagesToPdf()`, which converts images into a
  PDF (one page per image, implemented natively with `pdfbox-android` on
  Android and `CoreGraphics` on iOS), and `FlutterPdfPro.insertPages()`,
  which inserts another PDF's pages at a given position.
- Added a built-in "Add image" toolbar action (`showAddImage`,
  `onAddImageRequested`, `onImageAdded`) that lets the host app supply an
  image (e.g. from an image picker), then position and resize it over the
  current page before stamping it onto the document via the new
  `FlutterPdfPro.addImageToPdf()` method (implemented natively with
  `pdfbox-android` on Android and `CoreGraphics` on iOS).
