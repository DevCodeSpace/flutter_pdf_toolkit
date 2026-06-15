# flutter_pdf_toolkit

<img src="https://raw.githubusercontent.com/DevCodeSpace/flutter_pdf_toolkit/main/assets/banner.png" alt="flutter_pdf_toolkit"/>

A premium, high-performance, native PDF viewer plugin for Flutter. It renders PDFs smoothly via Flutter `PlatformView`s directly on top of platform-native PDF frameworks:

- **Android** — [`PdfRenderer`](https://developer.android.com/reference/android/graphics/pdf/PdfRenderer) for high-performance page rendering, combined with [`pdfbox-android`](https://github.com/TomRoush/PdfBox-Android) for text search and bookmark/outline extraction.
- **iOS** — [`PDFKit`](https://developer.apple.com/documentation/pdfkit) for full native rendering, text search, and outline support.

The plugin exposes a powerful Dart-side controller and an optional, fully-customizable built-in toolbar for common viewer interactions.

## Table of contents

- [Features](#features)
- [Platform support](#platform-support)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [PDF sources](#pdf-sources)
- [Widget reference (`FlutterPdfToolkit`)](#widget-reference-flutterpdftoolkit)
- [Controller reference (`FlutterPdfToolkitController`)](#controller-reference-flutterpdftoolkitcontroller)
- [Password-protected PDFs](#password-protected-pdfs)
- [Search](#search)
- [Bookmarks](#bookmarks)
- [Page thumbnails](#page-thumbnails)
- [Signing PDFs](#signing-pdfs)
- [Reordering pages](#reordering-pages)
- [Removing pages](#removing-pages)
- [Adding pages](#adding-pages)
- [Adding images to a PDF](#adding-images-to-a-pdf)
- [Merging, splitting, and downloading PDFs](#merging-splitting-and-downloading-pdfs)
- [Zoom](#zoom)
- [Dark mode](#dark-mode)
- [Limitations](#limitations)
- [Example app](#example-app)
- [Contributors](#contributors)

## Features

- Open PDFs from assets, network URLs, local file paths, raw bytes
  (`Uint8List`), or base64-encoded strings
- Built-in toolbar with page navigation, zoom controls, search, bookmarks,
  page thumbnails, and a theme toggle — each shown/hidden independently
- Programmatic control via `FlutterPdfToolkitController`: jump to page, next /
  previous page, zoom in / out / reset, search, bookmarks, dark mode, page
  thumbnails
- Horizontal or vertical scrolling, single-page or continuous page modes
- Pinch-to-zoom and double-tap-to-zoom on **both** Android and iOS
- Initial page and initial zoom level configuration
- Password-protected PDF support, with an automatic unlock dialog
- Dark mode toggle at the Flutter UI level
- Text search with result highlighting and bookmark/outline support on
  **both** Android and iOS
- Page thumbnails rendered natively from the PDF and shown in a grid for
  quick navigation
- Built-in "Sign document" toolbar action: draw a signature, position and
  resize it on the current page, and stamp it onto the PDF natively via
  `FlutterPdfToolkit.signPdf()`
- Built-in "Reorder pages" toolbar action: drag page thumbnails into a new
  order and save the rearranged PDF natively via
  `FlutterPdfToolkit.reorderPages()`
- Built-in "Delete pages" toolbar action: tap page thumbnails to mark them
  for removal and save the trimmed PDF natively via
  `FlutterPdfToolkit.removePages()`
- Built-in "Add pages" toolbar action: pick where to insert new pages from a
  page-thumbnail grid, then insert PDF and/or image files supplied by the
  host app natively via `FlutterPdfToolkit.insertPages()` and
  `FlutterPdfToolkit.imagesToPdf()`
- Built-in "Add image" toolbar action: pick an image supplied by the host
  app, position and resize it on the current page, and stamp it onto the PDF
  natively via `FlutterPdfToolkit.addImageToPdf()`
- Merge multiple PDF files into a single document natively via
  `FlutterPdfToolkit.mergePdfs()`
- Split a PDF into multiple documents by page range natively via
  `FlutterPdfToolkit.splitPdf()`, with `FlutterPdfToolkit.getPdfPageCount()` to read a
  PDF's page count
- Save or share a PDF file via `FlutterPdfToolkit.downloadPdf()` — saves to the
  Downloads folder on Android, or opens the share sheet on iOS

## Platform support

| Platform | Minimum version      | Rendering engine                 | Notes                                     |
| -------- | -------------------- | -------------------------------- | ----------------------------------------- |
| Android  | API 21 (Android 5.0) | `PdfRenderer` + `pdfbox-android` | Search and bookmarks via `pdfbox-android` |
| iOS      | iOS 13.0             | `PDFKit`                         | Full search and bookmark/outline support  |

Other platforms (web, desktop, macOS) are not implemented. `FlutterPdfToolkit`
renders the document via `AndroidView`/`UiKitView`, so using it outside
Android or iOS will fail at runtime rather than gracefully degrade.

## Requirements

- Flutter `>=1.17.0` and Dart SDK `^3.11.5` (as declared in `pubspec.yaml`).
- Android: `minSdkVersion 21` or higher (raise it in
  `android/app/build.gradle` if your app currently targets lower).
- iOS: deployment target `13.0` or higher (set `platform :ios, '13.0'` in
  your `ios/Podfile`).

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_pdf_toolkit: ^0.0.1
```

Then run:

```bash
flutter pub get
```

No additional native setup is required — the plugin registers its platform
views automatically on Android and iOS.

> If you load PDFs from the network, make sure your app has internet access
> permission (already enabled by default for Android, and allowed by default
> on iOS unless you've restricted App Transport Security).

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_pdf_toolkit/flutter_pdf_toolkit.dart';

class PdfScreen extends StatelessWidget {
  const PdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Viewer')),
      body: const FlutterPdfToolkit(
        source: PdfSource.network(
          'https://cdn.syncfusion.com/content/PDFViewer/flutter-succinctly.pdf',
        ),
      ),
    );
  }
}
```

### With a controller

A `FlutterPdfToolkitController` lets you drive the viewer programmatically and
read its current state (page number, zoom level, bookmarks, search results,
etc.).

```dart
class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  final FlutterPdfToolkitController _controller = FlutterPdfToolkitController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: _controller.nextPage,
          ),
        ],
      ),
      body: FlutterPdfToolkit(
        source: const PdfSource.asset('assets/sample.pdf'),
        controller: _controller,
      ),
    );
  }
}
```

## PDF sources

`PdfSource` is a sealed class with a factory constructor for each supported
input type:

```dart
// From an asset bundled with your app
const PdfSource.asset('assets/sample.pdf');
const PdfSource.asset('assets/sample.pdf', bundle: myAssetBundle);

// From a network URL, optionally with custom headers (e.g. auth tokens)
const PdfSource.network('https://example.com/sample.pdf');
const PdfSource.network(
  'https://example.com/sample.pdf',
  headers: {'Authorization': 'Bearer <token>'},
);

// From an absolute local file path
const PdfSource.filePath('/storage/emulated/0/Download/sample.pdf');

// From raw bytes (e.g. downloaded or generated in-memory)
PdfSource.bytes(bytes); // Uint8List

// From a base64-encoded string (data URLs such as
// "data:application/pdf;base64,..." are also accepted)
PdfSource.base64(base64PdfString);
PdfSource.base64(base64PdfString, password: 'secret');
```

Internally, asset, network, bytes, and base64 sources are written to a
temporary file before being handed to the native viewer; file path sources
are passed through as-is.

## Widget reference (`FlutterPdfToolkit`)

| Property                 | Type                                       | Default                   | Description                                                                                                      |
| ------------------------ | ------------------------------------------ | ------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `source`                 | `PdfSource`                                | —                         | **Required.** The PDF to display.                                                                                |
| `controller`             | `FlutterPdfToolkitController?`             | `null`                    | Controller used to drive and observe the viewer. If omitted, an internal controller is created.                  |
| `showToolbar`            | `bool`                                     | `true`                    | Show/hide the built-in toolbar.                                                                                  |
| `showSearch`             | `bool`                                     | `true`                    | Show the search icon in the toolbar.                                                                             |
| `showBookmarks`          | `bool`                                     | `true`                    | Show the bookmarks icon in the toolbar.                                                                          |
| `showThumbnails`         | `bool`                                     | `true`                    | Show the page-thumbnails icon in the toolbar.                                                                    |
| `showZoomControls`       | `bool`                                     | `true`                    | Show zoom in/out controls in the toolbar.                                                                        |
| `showPageControls`       | `bool`                                     | `true`                    | Show previous/next page controls in the toolbar.                                                                 |
| `showThemeToggle`        | `bool`                                     | `true`                    | Show the light/dark theme toggle in the toolbar.                                                                 |
| `showSignature`          | `bool`                                     | `true`                    | Show the "Sign document" icon in the toolbar (see [Signing PDFs](#signing-pdfs)).                                |
| `onSigned`               | `void Function(String signedFilePath)?`    | `null`                    | Called with the file path of the signed copy after the user completes the built-in signing flow.                 |
| `showReorder`            | `bool`                                     | `true`                    | Show the "Reorder pages" icon in the toolbar (see [Reordering pages](#reordering-pages)).                        |
| `onPagesReordered`       | `void Function(String reorderedFilePath)?` | `null`                    | Called with the file path of the reordered copy after the user completes the built-in reorder flow.              |
| `showDeletePages`        | `bool`                                     | `true`                    | Show the "Delete pages" icon in the toolbar (see [Removing pages](#removing-pages)).                             |
| `onPagesRemoved`         | `void Function(String updatedFilePath)?`   | `null`                    | Called with the file path of the trimmed copy after the user completes the built-in delete-pages flow.           |
| `showAddPages`           | `bool`                                     | `true`                    | Show the "Add pages" icon in the toolbar (see [Adding pages](#adding-pages)).                                    |
| `onAddPagesRequested`    | `Future<List<String>?> Function()?`        | `null`                    | Called after the user picks an insert position; should return local file paths (PDFs and/or images) to insert.   |
| `onPagesAdded`           | `void Function(String updatedFilePath)?`   | `null`                    | Called with the file path of the updated copy after the user completes the built-in add-pages flow.              |
| `showAddImage`           | `bool`                                     | `true`                    | Show the "Add image" icon in the toolbar (see [Adding images to a PDF](#adding-images-to-a-pdf)).                |
| `onAddImageRequested`    | `Future<Uint8List?> Function()?`           | `null`                    | Called when the user taps "Add image"; should return the bytes (JPEG/PNG) of the image to stamp onto the page.   |
| `onImageAdded`           | `void Function(String updatedFilePath)?`   | `null`                    | Called with the file path of the updated copy after the user completes the built-in add-image flow.              |
| `darkMode`               | `bool`                                     | `false`                   | Initial dark mode state for the native viewer.                                                                   |
| `toolbarBackgroundColor` | `Color?`                                   | theme surface color       | Background color of the built-in toolbar.                                                                        |
| `toolbarForegroundColor` | `Color?`                                   | theme `onSurface` color   | Icon/text color of the built-in toolbar.                                                                         |
| `backgroundColor`        | `Color?`                                   | theme scaffold background | Background color behind the PDF view (and shown while loading/on error).                                         |
| `initialZoomLevel`       | `double`                                   | `1.0`                     | Zoom level applied when the document first loads.                                                                |
| `initialPage`            | `int`                                      | `1`                       | Page shown when the document first loads (1-indexed).                                                            |
| `password`               | `String?`                                  | `null`                    | Password to use when opening an encrypted PDF. Takes precedence over a password supplied via `PdfSource.base64`. |
| `scrollDirection`        | `Axis`                                     | `Axis.vertical`           | `Axis.vertical` for vertical scrolling, `Axis.horizontal` for horizontal/page-swipe scrolling.                   |
| `singlePage`             | `bool`                                     | `false`                   | `true` shows one page at a time; `false` shows continuous scrolling pages.                                       |

If the toolbar is hidden (`showToolbar: false`), drive the viewer entirely
through a `FlutterPdfToolkitController`.

## Controller reference (`FlutterPdfToolkitController`)

`FlutterPdfToolkitController` extends `ChangeNotifier`, so you can listen to it
directly or wrap the viewer in an `AnimatedBuilder` / `ListenableBuilder` to
rebuild your own UI in response to state changes.

### State (read-only)

| Getter                     | Type                    | Description                                                  |
| -------------------------- | ----------------------- | ------------------------------------------------------------ |
| `pageNumber`               | `int`                   | Current page (1-indexed).                                    |
| `pageCount`                | `int`                   | Total number of pages in the document.                       |
| `zoomLevel`                | `double`                | Current zoom level.                                          |
| `isReady`                  | `bool`                  | Whether the native view has finished initializing.           |
| `errorMessage`             | `String?`               | Non-null if the document failed to load (e.g. invalid file). |
| `bookmarks`                | `List<PdfBookmarkItem>` | Outline/bookmarks reported by the platform.                  |
| `searchText`               | `String?`               | The active search query, if any.                             |
| `searchResultCount`        | `int`                   | Number of matches for the active search.                     |
| `currentSearchResultIndex` | `int`                   | Index (1-based) of the currently highlighted match.          |

### Actions

| Method                                                | Description                                                                                               |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `jumpToPage(int pageNumber)`                          | Jump directly to the given page (1-indexed).                                                              |
| `nextPage()`                                          | Go to the next page.                                                                                      |
| `previousPage()`                                      | Go to the previous page.                                                                                  |
| `zoomIn([double step = 0.25])`                        | Increase zoom by `step`.                                                                                  |
| `zoomOut([double step = 0.25])`                       | Decrease zoom by `step`.                                                                                  |
| `resetZoom()`                                         | Reset zoom to the default level.                                                                          |
| `search(String text, {bool caseSensitive = false})`   | Search the document for `text` (see [Search](#search)).                                                   |
| `clearSearch()`                                       | Clear the active search and highlights.                                                                   |
| `nextSearchResult()`                                  | Jump to the next search match.                                                                            |
| `previousSearchResult()`                              | Jump to the previous search match.                                                                        |
| `requestBookmarks()`                                  | Re-request the bookmark/outline list from the native side.                                                |
| `setDarkMode(bool enabled)`                           | Toggle dark mode in the native viewer.                                                                    |
| `getPageThumbnail(int pageNumber, {int width = 200})` | Returns a PNG-encoded `Uint8List?` thumbnail of the given page, rendered natively at `width` pixels wide. |

### `PdfBookmarkItem`

```dart
class PdfBookmarkItem {
  final String title;
  final int pageNumber;
}
```

## Password-protected PDFs

There are two ways to supply a password:

1. Pass `password` directly to `FlutterPdfToolkit`:

   ```dart
   FlutterPdfToolkit(
     source: const PdfSource.filePath('/path/to/protected.pdf'),
     password: 'samplefiles',
   )
   ```

2. Attach a password to a `PdfSource.base64` source:

   ```dart
   FlutterPdfToolkit(
     source: PdfSource.base64(base64PdfString, password: 'samplefiles'),
   )
   ```

If no password is supplied (or the supplied password is incorrect), the
widget shows a built-in **"Password Required"** dialog and prompts the user
to enter the password. The dialog re-displays with an "Incorrect password"
error if the entered password is rejected, and can be cancelled to abort
loading the document.

## Search

- Text search is supported on **both Android and iOS**.
  - On iOS, search uses `PDFKit`'s native text search.
  - On Android, the page text is extracted with `pdfbox-android` (cached
    after first use) and matched case-insensitively.
- Matches are highlighted on the page and the view automatically scrolls to
  the first/selected match.
- Use `controller.search('query')`, `nextSearchResult()`,
  `previousSearchResult()`, and `clearSearch()` to drive search
  programmatically. The toolbar reflects the active query and match count
  when present.

## Bookmarks

- Bookmarks (PDF outline entries) are populated automatically on view
  creation via `requestBookmarks()` and exposed through
  `controller.bookmarks`.
- Tapping the bookmarks icon in the toolbar opens a bottom sheet listing all
  bookmarks; tapping an entry jumps to that page.
- Supported on **both Android and iOS** — Android extracts the document
  outline with `pdfbox-android`, while iOS reads it via `PDFKit`'s
  `outlineRoot`. If a PDF has no outline/bookmarks defined, `bookmarks` will
  be empty on either platform.

## Page thumbnails

- Tapping the thumbnails icon in the toolbar opens a grid of page previews;
  tapping a thumbnail jumps to that page.
- Each thumbnail is rendered natively (via `PDFKit` on iOS and `PdfRenderer`
  on Android) and fetched lazily as the grid is shown, then cached for the
  lifetime of the document.
- Use `controller.getPageThumbnail(pageNumber, width: 200)` to fetch a
  thumbnail yourself, e.g. to build a custom page picker.

## Signing PDFs

- Tapping the "Sign document" icon (the pen/draw icon) in the toolbar opens a
  built-in flow:
  1. A dialog where the user draws their signature with a finger/stylus
     (powered by `SignaturePad`).
  2. A bottom sheet showing a preview of the current page, where the user can
     drag and resize the signature before confirming placement.
  3. The signature is stamped onto the current page natively and the viewer
     reloads the signed copy. `onSigned` is called with the path to the new
     file.
- Hide the built-in action with `showSignature: false` if you want to build
  your own signing UI.
- `SignaturePad` and `SignaturePadController` are exported so you can build a
  custom signature-capture UI:

  ```dart
  final SignaturePadController controller = SignaturePadController();
  final GlobalKey<SignaturePadState> padKey = GlobalKey<SignaturePadState>();

  SignaturePad(key: padKey, controller: controller);

  // Later, e.g. when the user taps "Done":
  final Uint8List? pngBytes = await padKey.currentState?.toPngBytes();
  ```

  `toPngBytes()` renders the drawn strokes to a transparent PNG. Call
  `controller.clear()` to reset the pad and `controller.isEmpty` to check
  whether anything has been drawn.

- Stamp a signature (or any PNG image) onto a PDF page yourself with
  `FlutterPdfToolkit.signPdf()`:

  ```dart
  final String? signedPath = await FlutterPdfToolkit.signPdf(
    sourcePath: '/path/to/document.pdf',
    outputPath: '/path/to/output/signed.pdf',
    signatureImageBytes: pngBytes,
    pageNumber: 1, // 1-indexed
    xRatio: 0.6,   // left edge, as a fraction of the page width
    yRatio: 0.8,   // top edge, as a fraction of the page height
    widthRatio: 0.3,  // signature width, as a fraction of the page width
    heightRatio: 0.1, // signature height, as a fraction of the page height
  );
  ```

  | Parameter                    | Type        | Description                                                                               |
  | ---------------------------- | ----------- | ----------------------------------------------------------------------------------------- |
  | `sourcePath`                 | `String`    | Absolute file path of the PDF to sign.                                                    |
  | `outputPath`                 | `String`    | Absolute file path where the signed PDF should be written.                                |
  | `signatureImageBytes`        | `Uint8List` | PNG image to stamp onto the page, ideally with a transparent background.                  |
  | `pageNumber`                 | `int`       | 1-indexed page number to stamp the signature onto.                                        |
  | `xRatio` / `yRatio`          | `double`    | Top-left position of the signature, as a fraction (`0.0`-`1.0`) of the page width/height. |
  | `widthRatio` / `heightRatio` | `double`    | Size of the signature, as a fraction (`0.0`-`1.0`) of the page width/height.              |

  Returns `outputPath` on success, or `null` if signing failed. Runs
  natively — `pdfbox-android` on Android (appended to the page's content
  stream) and `CoreGraphics` on iOS (the page is redrawn into a new PDF
  context with the signature composited on top) — so `sourcePath` must be a
  local file path and existing vector content is preserved.

## Reordering pages

- Tapping the "Reorder pages" icon (the swap icon) in the toolbar opens a
  built-in flow:
  1. A bottom sheet shows every page as a thumbnail in a grid.
  2. The user presses and holds a page, then drags it to a new position.
     Each tile shows a badge with its current position in the new order.
  3. Tapping "Save order" rewrites the document with the pages in their new
     order natively, and the viewer reloads the rearranged copy.
     `onPagesReordered` is called with the path to the new file.
- Hide the built-in action with `showReorder: false` if you want to build
  your own reordering UI.

- Reorder (and optionally drop) pages yourself with
  `FlutterPdfToolkit.reorderPages()`:

  ```dart
  final String? reorderedPath = await FlutterPdfToolkit.reorderPages(
    path: '/path/to/document.pdf',
    outputPath: '/path/to/output/reordered.pdf',
    pageOrder: [3, 1, 2], // moves page 3 to the front, drops the rest
  );
  ```

  | Parameter    | Type        | Description                                                                                                  |
  | ------------ | ----------- | ------------------------------------------------------------------------------------------------------------ |
  | `path`       | `String`    | Absolute file path of the PDF to reorder.                                                                    |
  | `outputPath` | `String`    | Absolute file path where the reordered PDF should be written.                                                |
  | `pageOrder`  | `List<int>` | 1-based page numbers from the source PDF, in the desired output order. Omit a page number to drop that page. |

  Returns `outputPath` on success, or `null` if reordering failed. Runs
  natively — `pdfbox-android` on Android and `PDFKit` on iOS — so `path` must
  be a local file path. Use `getPdfPageCount()` to determine valid page
  numbers beforehand.

## Removing pages

- Tapping the "Delete pages" icon (the trash icon) in the toolbar opens a
  built-in flow:
  1. A bottom sheet shows every page as a thumbnail in a grid.
  2. The user taps pages to mark them for removal. Selected pages are
     highlighted with a checkmark.
  3. Tapping "Delete N pages" rewrites the document without the selected
     pages natively, and the viewer reloads the trimmed copy.
     `onPagesRemoved` is called with the path to the new file.
- Hide the built-in action with `showDeletePages: false` if you want to
  build your own page-removal UI.

- Remove pages yourself with `FlutterPdfToolkit.removePages()`:

  ```dart
  final String? trimmedPath = await FlutterPdfToolkit.removePages(
    path: '/path/to/document.pdf',
    outputPath: '/path/to/output/trimmed.pdf',
    pageNumbers: [2, 4], // removes pages 2 and 4
  );
  ```

  | Parameter     | Type        | Description                                                 |
  | ------------- | ----------- | ----------------------------------------------------------- |
  | `path`        | `String`    | Absolute file path of the PDF to trim.                      |
  | `outputPath`  | `String`    | Absolute file path where the trimmed PDF should be written. |
  | `pageNumbers` | `List<int>` | 1-based page numbers from the source PDF to remove.         |

  Returns `outputPath` on success, or `null` if removal failed (including if
  `pageNumbers` covers every page in the document). Runs natively —
  `pdfbox-android` on Android and `PDFKit` on iOS — so `path` must be a local
  file path. Use `getPdfPageCount()` to determine valid page numbers
  beforehand.

## Adding pages

- Tapping the "Add pages" icon (the document-plus icon) in the toolbar opens
  a built-in flow:
  1. A bottom sheet shows every page as a thumbnail in a grid, plus a
     "Start" tile. Tap a page to insert the new pages after it (or tap
     "Start" to insert them before page 1).
  2. `onAddPagesRequested` is called — your app should show its own file
     and/or image picker here and return the chosen local file paths, in the
     order they should be inserted. Return `null` or an empty list to cancel.
  3. Any image files (`.jpg`, `.jpeg`, `.png`, `.heic`, `.heif`, `.webp`,
     `.bmp`, `.gif`) are converted to single-page PDFs and combined with any
     PDF files, preserving the given order. The combined pages are inserted
     at the chosen position natively, and the viewer reloads the updated
     copy. `onPagesAdded` is called with the path to the new file.
- `showAddPages` defaults to `true`, but the action requires
  `onAddPagesRequested` to be provided — without it, tapping the icon shows a
  message that adding pages isn't configured. Set `showAddPages: false` if
  you want to build your own add-pages UI instead.

- Insert another PDF's pages yourself with `FlutterPdfToolkit.insertPages()`:

  ```dart
  final String? updatedPath = await FlutterPdfToolkit.insertPages(
    path: '/path/to/document.pdf',
    insertPath: '/path/to/pages_to_insert.pdf',
    outputPath: '/path/to/output/updated.pdf',
    afterPageNumber: 2, // insert after page 2 (0 = before page 1)
  );
  ```

  | Parameter         | Type     | Description                                                                                                       |
  | ----------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
  | `path`            | `String` | Absolute file path of the PDF to insert pages into.                                                               |
  | `insertPath`      | `String` | Absolute file path of the PDF whose pages should be inserted.                                                     |
  | `outputPath`      | `String` | Absolute file path where the updated PDF should be written.                                                       |
  | `afterPageNumber` | `int`    | 1-based page number to insert after; `0` inserts before page 1, and the document's page count appends at the end. |

  Returns `outputPath` on success, or `null` if insertion failed. Runs
  natively — `pdfbox-android` on Android and `PDFKit` on iOS — so both `path`
  and `insertPath` must be local file paths.

- Convert images into a PDF (one page per image) with
  `FlutterPdfToolkit.imagesToPdf()`:

  ```dart
  final String? pagesPath = await FlutterPdfToolkit.imagesToPdf(
    imagePaths: ['/path/to/photo1.jpg', '/path/to/photo2.png'],
    outputPath: '/path/to/output/photos.pdf',
  );
  ```

  | Parameter    | Type           | Description                                                   |
  | ------------ | -------------- | ------------------------------------------------------------- |
  | `imagePaths` | `List<String>` | Absolute file paths of the images to convert, in page order.  |
  | `outputPath` | `String`       | Absolute file path where the resulting PDF should be written. |

  Returns `outputPath` on success, or `null` if conversion failed. Each page
  is sized to match its source image. Runs natively — `pdfbox-android` on
  Android and `CoreGraphics` on iOS.

## Adding images to a PDF

- Tapping the "Add image" icon (the image-plus icon) in the toolbar opens a
  built-in flow:
  1. `onAddImageRequested` is called — your app should show its own image
     picker (e.g. via the `image_picker` package) and return the chosen
     image's bytes (JPEG or PNG). Return `null` to cancel.
  2. A bottom sheet shows a preview of the current page, where the user can
     drag and resize the image before confirming placement.
  3. The image is stamped onto the current page natively and the viewer
     reloads the updated copy. `onImageAdded` is called with the path to the
     new file.
- `showAddImage` defaults to `true`, but the action requires
  `onAddImageRequested` to be provided — without it, tapping the icon shows a
  message that adding images isn't configured. Set `showAddImage: false` if
  you want to build your own add-image UI instead.

- Stamp an image onto a PDF page yourself with `FlutterPdfToolkit.addImageToPdf()`:

  ```dart
  final String? updatedPath = await FlutterPdfToolkit.addImageToPdf(
    sourcePath: '/path/to/document.pdf',
    outputPath: '/path/to/output/with_image.pdf',
    imageBytes: imageBytes, // JPEG or PNG bytes
    pageNumber: 1, // 1-indexed
    xRatio: 0.1,   // left edge, as a fraction of the page width
    yRatio: 0.1,   // top edge, as a fraction of the page height
    widthRatio: 0.3,  // image width, as a fraction of the page width
    heightRatio: 0.3, // image height, as a fraction of the page height
  );
  ```

  | Parameter                    | Type        | Description                                                                           |
  | ---------------------------- | ----------- | ------------------------------------------------------------------------------------- |
  | `sourcePath`                 | `String`    | Absolute file path of the PDF to modify.                                              |
  | `outputPath`                 | `String`    | Absolute file path where the updated PDF should be written.                           |
  | `imageBytes`                 | `Uint8List` | JPEG or PNG image to stamp onto the page.                                             |
  | `pageNumber`                 | `int`       | 1-indexed page number to stamp the image onto.                                        |
  | `xRatio` / `yRatio`          | `double`    | Top-left position of the image, as a fraction (`0.0`-`1.0`) of the page width/height. |
  | `widthRatio` / `heightRatio` | `double`    | Size of the image, as a fraction (`0.0`-`1.0`) of the page width/height.              |

  Returns `outputPath` on success, or `null` if adding the image failed. Runs
  natively — `pdfbox-android` on Android (appended to the page's content
  stream) and `CoreGraphics` on iOS (the page is redrawn into a new PDF
  context with the image composited on top) — so `sourcePath` must be a
  local file path and existing vector content is preserved.

## Merging, splitting, and downloading PDFs

`FlutterPdfToolkit` exposes several static helper methods that don't require a
viewer instance — they call straight into the native platform code via a
shared method channel.

### Merging PDFs

```dart
final String? mergedPath = await FlutterPdfToolkit.mergePdfs(
  paths: ['/path/to/first.pdf', '/path/to/second.pdf'],
  outputPath: '/path/to/output/merged.pdf',
);

if (mergedPath != null) {
  // Open it in the viewer, e.g.:
  // FlutterPdfToolkit(source: PdfSource.filePath(mergedPath));
}
```

| Parameter    | Type           | Description                                                                |
| ------------ | -------------- | -------------------------------------------------------------------------- |
| `paths`      | `List<String>` | Absolute file paths of the PDFs to merge, in the order they should appear. |
| `outputPath` | `String`       | Absolute file path where the merged PDF should be written.                 |

Returns the `outputPath` on success, or `null` if merging failed (e.g. an
invalid or unreadable input path). The merge is performed natively —
`PDFKit` on iOS and `pdfbox-android` on Android — so all input paths must be
local file paths. If a source is an asset, network URL, or in-memory bytes,
write it to a temporary file first (see [PDF sources](#pdf-sources)).

### Getting a PDF's page count

```dart
final int? pageCount = await FlutterPdfToolkit.getPdfPageCount('/path/to/document.pdf');
```

Returns the total number of pages, or `null` if the file could not be read.
Useful for working out valid page ranges before calling `splitPdf()`.

### Splitting a PDF

```dart
final List<String>? files = await FlutterPdfToolkit.splitPdf(
  path: '/path/to/document.pdf',
  outputDirectory: '/path/to/output',
  pageRanges: [
    [1, 3], // pages 1-3 -> split_1.pdf
    [4, 4], // page 4    -> split_2.pdf
    [5, 10], // pages 5-10 -> split_3.pdf
  ],
);

if (files != null) {
  for (final path in files) {
    // e.g. open one of the resulting files in the viewer:
    // FlutterPdfToolkit(source: PdfSource.filePath(path));
  }
}
```

| Parameter              | Type              | Description                                                                                         |
| ---------------------- | ----------------- | --------------------------------------------------------------------------------------------------- |
| `path`                 | `String`          | Absolute file path of the PDF to split.                                                             |
| `outputDirectory`      | `String`          | Absolute path of the directory where split files are written (created if it doesn't exist).         |
| `pageRanges`           | `List<List<int>>` | One `[startPage, endPage]` pair per output file, 1-based and inclusive (e.g. `[1, 3]` = pages 1-3). |
| `outputFileNamePrefix` | `String`          | Optional prefix for output file names. Defaults to `'split'`. Files are named `<prefix>_<n>.pdf`.   |

Returns the list of output file paths, in the same order as `pageRanges`, or
`null` if splitting failed (e.g. an invalid path or an out-of-range page
number). Like `mergePdfs()`, this runs natively via `PDFKit` on iOS and
`pdfbox-android` on Android, and `path` must be a local file path.

### Downloading / sharing a PDF

```dart
final bool success = await FlutterPdfToolkit.downloadPdf(
  sourcePath: '/path/to/merged.pdf',
  fileName: 'merged_document.pdf',
);
```

| Parameter    | Type     | Description                                     |
| ------------ | -------- | ----------------------------------------------- |
| `sourcePath` | `String` | Absolute path of the PDF file to save or share. |
| `fileName`   | `String` | Suggested file name for the saved/shared copy.  |

- On **Android**, the file is copied into the device's public Downloads
  folder under `fileName`.
- On **iOS**, the system share sheet is opened so the user can save the file
  to Files, AirDrop it, etc.

Returns `true` if the save/share action completed successfully, `false`
otherwise.

## Zoom

- Pinch-to-zoom is supported on both platforms via the built-in scroll/zoom
  view.
- Double-tapping the page toggles between the default zoom level and 2x zoom,
  centered on the tap location, on both Android and iOS.
- `controller.zoomIn()`, `zoomOut()`, and `resetZoom()` drive zoom
  programmatically; the toolbar's zoom buttons call these directly.

## Dark mode

- `darkMode` sets the initial state of the native viewer's color scheme.
- The built-in toolbar includes a sun/moon toggle (`showThemeToggle`) that
  calls `controller.setDarkMode(...)` and rebuilds the toolbar's icon.
- `controller.setDarkMode(bool enabled)` can be called at any time —
  including before the native view is ready, in which case it is applied
  once the view finishes initializing.
- Dark mode only affects the PDF viewer's chrome/background at the native
  level; it does not alter the content of the PDF itself.

## Limitations

- Only Android and iOS are currently supported — there is no web, desktop,
  or macOS implementation.

- Search is case-insensitive on both platforms; advanced query syntax
  (regex, whole-word, etc.) is not supported.

## Example app

The [`example/`](example/) directory contains a full demo app that exercises
every feature described in this README: opening PDFs from assets, network
URLs, file paths, bytes, and base64 (including a password-protected sample);
the built-in toolbar with search, bookmarks, thumbnails, zoom, and dark mode;
and the signing, reordering, delete-pages, add-pages, add-image, merge,
split, and download flows.

Run it with:

```bash
cd example
flutter run
```

## Contributors

<img src="https://raw.githubusercontent.com/DevCodeSpace/flutter_pdf_toolkit/main/assets/contributors.png" width="250"/>

---

> Made with ❤️ by the DevCodeSpace
