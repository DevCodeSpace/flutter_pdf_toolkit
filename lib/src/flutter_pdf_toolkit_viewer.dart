import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flutter_pdf_toolkit_controller.dart';
import 'pdf_source.dart';
import 'signature_pad.dart';

class FlutterPdfToolkit extends StatefulWidget {
  const FlutterPdfToolkit({
    super.key,
    required this.source,
    this.controller,
    this.showToolbar = true,
    this.showSearch = true,
    this.showBookmarks = true,
    this.showThumbnails = true,
    this.showZoomControls = true,
    this.showPageControls = true,
    this.showThemeToggle = true,
    this.showSignature = true,
    this.showReorder = true,
    this.showDeletePages = true,
    this.showAddPages = true,
    this.showAddImage = true,
    this.darkMode = false,
    this.toolbarBackgroundColor,
    this.toolbarForegroundColor,
    this.backgroundColor,
    this.initialZoomLevel = 1.0,
    this.initialPage = 1,
    this.password,
    this.scrollDirection = Axis.vertical,
    this.singlePage = false,
    this.onSigned,
    this.onPagesReordered,
    this.onPagesRemoved,
    this.onAddPagesRequested,
    this.onPagesAdded,
    this.onAddImageRequested,
    this.onImageAdded,
  });

  final PdfSource source;
  final FlutterPdfToolkitController? controller;
  final bool showToolbar;
  final bool showSearch;
  final bool showBookmarks;
  final bool showThumbnails;
  final bool showZoomControls;
  final bool showPageControls;
  final bool showThemeToggle;
  final bool showSignature;
  final bool showReorder;
  final bool showDeletePages;
  final bool showAddPages;
  final bool showAddImage;
  final bool darkMode;
  final Color? toolbarBackgroundColor;
  final Color? toolbarForegroundColor;
  final Color? backgroundColor;
  final double initialZoomLevel;
  final int initialPage;
  final String? password;
  final Axis scrollDirection;
  final bool singlePage;

  /// Called after the user signs the document via the built-in "Sign"
  /// toolbar action, with the file path of the newly-signed PDF copy.
  final void Function(String signedFilePath)? onSigned;

  /// Called after the user reorders pages via the built-in "Reorder pages"
  /// toolbar action, with the file path of the newly-reordered PDF copy.
  final void Function(String reorderedFilePath)? onPagesReordered;

  /// Called after the user removes pages via the built-in "Delete pages"
  /// toolbar action, with the file path of the newly-trimmed PDF copy.
  final void Function(String updatedFilePath)? onPagesRemoved;

  /// Called when the user taps the built-in "Add pages" toolbar action,
  /// after they've chosen where to insert the new pages.
  ///
  /// The implementation should let the user pick one or more PDF or image
  /// files (e.g. via a file/image picker) and return their local file paths,
  /// in the order they should be inserted. Return `null` or an empty list to
  /// cancel.
  final Future<List<String>?> Function()? onAddPagesRequested;

  /// Called after the user adds pages via the built-in "Add pages" toolbar
  /// action, with the file path of the newly-updated PDF copy.
  final void Function(String updatedFilePath)? onPagesAdded;

  /// Called when the user taps the built-in "Add image" toolbar action.
  ///
  /// The implementation should let the user pick an image (e.g. via an
  /// image picker) and return its bytes (JPEG or PNG). Return `null` to
  /// cancel.
  final Future<Uint8List?> Function()? onAddImageRequested;

  /// Called after the user adds an image via the built-in "Add image"
  /// toolbar action, with the file path of the newly-updated PDF copy.
  final void Function(String updatedFilePath)? onImageAdded;

  static const MethodChannel _globalChannel = MethodChannel(
    'flutter_pdf_toolkit',
  );

  /// Merges multiple PDF files into a single PDF file at [outputPath].
  /// Returns the output path of the merged PDF if successful, or null otherwise.
  static Future<String?> mergePdfs({
    required List<String> paths,
    required String outputPath,
  }) async {
    try {
      final String? result = await _globalChannel.invokeMethod<String>(
        'mergePdfs',
        {'paths': paths, 'outputPath': outputPath},
      );
      return result;
    } catch (e) {
      debugPrint('Error merging PDFs: $e');
      return null;
    }
  }

  /// Returns the total number of pages in the PDF at [path], or null if the
  /// file could not be read.
  static Future<int?> getPdfPageCount(String path) async {
    try {
      final int? result = await _globalChannel.invokeMethod<int>(
        'getPdfPageCount',
        {'path': path},
      );
      return result;
    } catch (e) {
      debugPrint('Error getting PDF page count: $e');
      return null;
    }
  }

  /// Splits the PDF at [path] into multiple PDF files written to
  /// [outputDirectory], one file per entry in [pageRanges].
  ///
  /// Each entry in [pageRanges] is a `[startPage, endPage]` pair, using
  /// 1-based, inclusive page numbers (e.g. `[1, 3]` extracts pages 1-3).
  /// A single-page range can be written as `[pageNumber, pageNumber]`.
  ///
  /// Output files are named `<outputFileNamePrefix>_<n>.pdf`, where `<n>` is
  /// the 1-based index of the range in [pageRanges].
  ///
  /// Returns the list of output file paths, in the same order as
  /// [pageRanges], or null if splitting failed (e.g. an invalid path or an
  /// out-of-range page number).
  static Future<List<String>?> splitPdf({
    required String path,
    required String outputDirectory,
    required List<List<int>> pageRanges,
    String outputFileNamePrefix = 'split',
  }) async {
    try {
      final List<dynamic>? result = await _globalChannel
          .invokeMethod<List<dynamic>>('splitPdf', {
            'path': path,
            'outputDirectory': outputDirectory,
            'pageRanges': pageRanges,
            'outputFileNamePrefix': outputFileNamePrefix,
          });
      return result?.cast<String>();
    } catch (e) {
      debugPrint('Error splitting PDF: $e');
      return null;
    }
  }

  /// Downloads/Saves a PDF file to the device\'s public Downloads folder (on Android)
  /// or opens a share sheet to let the user save/share it (on iOS).
  /// Returns true if successful.
  static Future<bool> downloadPdf({
    required String sourcePath,
    required String fileName,
  }) async {
    try {
      final bool? result = await _globalChannel.invokeMethod<bool>(
        'downloadPdf',
        {'sourcePath': sourcePath, 'fileName': fileName},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error downloading PDF: $e');
      return false;
    }
  }

  /// Stamps [signatureImageBytes] (a PNG, ideally with a transparent
  /// background) onto page [pageNumber] (1-indexed) of the PDF at
  /// [sourcePath], writing the result to [outputPath].
  ///
  /// [xRatio] and [yRatio] are the position of the signature's top-left
  /// corner as a fraction of the page width/height (`0.0`-`1.0`), and
  /// [widthRatio]/[heightRatio] are its size as a fraction of the page
  /// width/height.
  ///
  /// Returns [outputPath] on success, or `null` if signing failed. Runs
  /// natively via `pdfbox-android` on Android and `CoreGraphics` on iOS, so
  /// [sourcePath] must be a local file path.
  static Future<String?> signPdf({
    required String sourcePath,
    required String outputPath,
    required Uint8List signatureImageBytes,
    required int pageNumber,
    required double xRatio,
    required double yRatio,
    required double widthRatio,
    required double heightRatio,
  }) async {
    try {
      final String? result = await _globalChannel
          .invokeMethod<String>('signPdf', {
            'sourcePath': sourcePath,
            'outputPath': outputPath,
            'signatureBytes': signatureImageBytes,
            'pageNumber': pageNumber,
            'xRatio': xRatio,
            'yRatio': yRatio,
            'widthRatio': widthRatio,
            'heightRatio': heightRatio,
          });
      return result;
    } catch (e) {
      debugPrint('Error signing PDF: $e');
      return null;
    }
  }

  /// Stamps [imageBytes] (a JPEG or PNG image) onto page [pageNumber]
  /// (1-indexed) of the PDF at [sourcePath], writing the result to
  /// [outputPath].
  ///
  /// [xRatio] and [yRatio] are the position of the image's top-left corner
  /// as a fraction of the page width/height (`0.0`-`1.0`), and
  /// [widthRatio]/[heightRatio] are its size as a fraction of the page
  /// width/height.
  ///
  /// Returns [outputPath] on success, or `null` if adding the image failed.
  /// Runs natively via `pdfbox-android` on Android and `CoreGraphics` on
  /// iOS, so [sourcePath] must be a local file path.
  static Future<String?> addImageToPdf({
    required String sourcePath,
    required String outputPath,
    required Uint8List imageBytes,
    required int pageNumber,
    required double xRatio,
    required double yRatio,
    required double widthRatio,
    required double heightRatio,
  }) async {
    try {
      final String? result = await _globalChannel
          .invokeMethod<String>('addImageToPdf', {
            'sourcePath': sourcePath,
            'outputPath': outputPath,
            'imageBytes': imageBytes,
            'pageNumber': pageNumber,
            'xRatio': xRatio,
            'yRatio': yRatio,
            'widthRatio': widthRatio,
            'heightRatio': heightRatio,
          });
      return result;
    } catch (e) {
      debugPrint('Error adding image to PDF: $e');
      return null;
    }
  }

  /// Reorders (and optionally drops) the pages of the PDF at [path],
  /// writing the result to [outputPath].
  ///
  /// [pageOrder] is a list of 1-based page numbers from the source PDF, in
  /// the desired output order — e.g. `[3, 1, 2]` moves page 3 to the front.
  /// Page numbers may be omitted to drop those pages, but each entry must be
  /// a valid page number (use [getPdfPageCount] to determine the valid
  /// range).
  ///
  /// Returns [outputPath] on success, or `null` if reordering failed. Runs
  /// natively via `pdfbox-android` on Android and `PDFKit` on iOS, so [path]
  /// must be a local file path.
  static Future<String?> reorderPages({
    required String path,
    required String outputPath,
    required List<int> pageOrder,
  }) async {
    try {
      final String? result = await _globalChannel.invokeMethod<String>(
        'reorderPdf',
        {'path': path, 'outputPath': outputPath, 'pageOrder': pageOrder},
      );
      return result;
    } catch (e) {
      debugPrint('Error reordering PDF pages: $e');
      return null;
    }
  }

  /// Removes the pages at [pageNumbers] (1-based) from the PDF at [path],
  /// writing the result to [outputPath].
  ///
  /// All other pages are kept in their original order. [pageNumbers] must
  /// not cover every page in the document (use [getPdfPageCount] to
  /// determine the valid range).
  ///
  /// Returns [outputPath] on success, or `null` if removal failed.
  static Future<String?> removePages({
    required String path,
    required String outputPath,
    required List<int> pageNumbers,
  }) async {
    try {
      final int? pageCount = await getPdfPageCount(path);
      if (pageCount == null) {
        return null;
      }

      final Set<int> toRemove = pageNumbers.toSet();
      final List<int> pageOrder = [
        for (int pageNumber = 1; pageNumber <= pageCount; pageNumber++)
          if (!toRemove.contains(pageNumber)) pageNumber,
      ];

      if (pageOrder.isEmpty) {
        debugPrint(
          'Error removing PDF pages: cannot remove every page from a document',
        );
        return null;
      }

      return await reorderPages(
        path: path,
        outputPath: outputPath,
        pageOrder: pageOrder,
      );
    } catch (e) {
      debugPrint('Error removing PDF pages: $e');
      return null;
    }
  }

  /// Converts [imagePaths] (local image file paths, e.g. JPEG or PNG) into a
  /// single PDF written to [outputPath], one page per image in the given
  /// order, with each page sized to match its source image.
  ///
  /// Returns [outputPath] on success, or `null` if conversion failed.
  static Future<String?> imagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
  }) async {
    try {
      final String? result = await _globalChannel.invokeMethod<String>(
        'imagesToPdf',
        {'imagePaths': imagePaths, 'outputPath': outputPath},
      );
      return result;
    } catch (e) {
      debugPrint('Error converting images to PDF: $e');
      return null;
    }
  }

  /// Inserts all pages of [insertPath] (a PDF) into the PDF at [path] after
  /// page [afterPageNumber], writing the result to [outputPath].
  ///
  /// [afterPageNumber] is 1-based; use `0` to insert the new pages before the
  /// first page, or the document's page count (see [getPdfPageCount]) to
  /// append them at the end.
  ///
  /// Returns [outputPath] on success, or `null` if insertion failed.
  static Future<String?> insertPages({
    required String path,
    required String insertPath,
    required String outputPath,
    required int afterPageNumber,
  }) async {
    try {
      final int? pageCount = await getPdfPageCount(path);
      if (pageCount == null) {
        return null;
      }

      final int position = afterPageNumber.clamp(0, pageCount);

      if (position == 0) {
        return await mergePdfs(
          paths: [insertPath, path],
          outputPath: outputPath,
        );
      }
      if (position == pageCount) {
        return await mergePdfs(
          paths: [path, insertPath],
          outputPath: outputPath,
        );
      }

      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_insert_split',
      );
      final List<String>? parts = await splitPdf(
        path: path,
        outputDirectory: tempDir.path,
        pageRanges: [
          [1, position],
          [position + 1, pageCount],
        ],
      );
      if (parts == null || parts.length != 2) {
        return null;
      }

      return await mergePdfs(
        paths: [parts[0], insertPath, parts[1]],
        outputPath: outputPath,
      );
    } catch (e) {
      debugPrint('Error inserting PDF pages: $e');
      return null;
    }
  }

  @override
  State<FlutterPdfToolkit> createState() => _FlutterPdfToolkitState();
}

class _FlutterPdfToolkitState extends State<FlutterPdfToolkit> {
  late FlutterPdfToolkitController _controller;
  late Future<String> _resolvedPath;
  bool _darkMode = false;
  bool _isSigning = false;
  bool _isReordering = false;
  bool _isDeletingPages = false;
  bool _isAddingPages = false;
  bool _isAddingImage = false;
  final Map<int, Uint8List?> _thumbnailCache = {};

  bool get _supportsSearch =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _darkMode = widget.darkMode;
    _resolvedPath = widget.source.resolveToFile();
    _controller = widget.controller ?? FlutterPdfToolkitController();
    _controller.onPasswordRequired = _handlePasswordRequired;
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant FlutterPdfToolkit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.darkMode != widget.darkMode) {
      _darkMode = widget.darkMode;
      _controller.setDarkMode(_darkMode);
    }
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onControllerChanged);
      _controller.onPasswordRequired = null;
      _controller = widget.controller ?? FlutterPdfToolkitController();
      _controller.onPasswordRequired = _handlePasswordRequired;
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.onPasswordRequired = null;
    super.dispose();
  }

  void _attachChannel(int id) {
    _thumbnailCache.clear();
    _controller.attachChannel(MethodChannel('flutter_pdf_toolkit_view_$id'));
    unawaited(_controller.requestBookmarks());
  }

  Future<void> _showSearchDialog() async {
    if (!_supportsSearch) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Search not available'),
            content: const Text(
              'Text search is supported on Android and iOS only. The current platform is not supported.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    final TextEditingController textController = TextEditingController();
    final bool? search = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Search in PDF'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter search text'),
            onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );

    if (search == true && textController.text.trim().isNotEmpty) {
      await _controller.search(textController.text.trim());
    }
  }

  void _showBookmarks() {
    if (_controller.bookmarks.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('No bookmarks'),
            content: const Text(
              'This PDF does not expose any bookmarks on the current platform.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return ListView.separated(
          itemCount: _controller.bookmarks.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final PdfBookmarkItem bookmark = _controller.bookmarks[index];
            return ListTile(
              title: Text(bookmark.title),
              subtitle: Text('Page ${bookmark.pageNumber}'),
              onTap: () {
                _controller.jumpToPage(bookmark.pageNumber);
                Navigator.of(context).pop();
              },
            );
          },
        );
      },
    );
  }

  Future<Uint8List?> _loadThumbnail(int pageNumber) async {
    if (_thumbnailCache.containsKey(pageNumber)) {
      return _thumbnailCache[pageNumber];
    }
    final Uint8List? data = await _controller.getPageThumbnail(pageNumber);
    _thumbnailCache[pageNumber] = data;
    return data;
  }

  void _showThumbnails() {
    final int pageCount = _controller.pageCount;
    if (pageCount <= 0) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: pageCount,
            itemBuilder: (BuildContext context, int index) {
              final int pageNumber = index + 1;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  _controller.jumpToPage(pageNumber);
                  Navigator.of(context).pop();
                },
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: _loadThumbnail(pageNumber),
                        builder:
                            (
                              BuildContext context,
                              AsyncSnapshot<Uint8List?> snapshot,
                            ) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final Uint8List? data = snapshot.data;
                              if (data == null) {
                                return Center(child: Text('Page $pageNumber'));
                              }
                              return Image.memory(data, fit: BoxFit.cover);
                            },
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha((0.55 * 255).round()),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$pageNumber',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _startSignFlow() async {
    final SignaturePadController padController = SignaturePadController();
    final GlobalKey<SignaturePadState> padKey = GlobalKey<SignaturePadState>();

    final Uint8List? signature = await showDialog<Uint8List>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Draw your signature'),
          content: SizedBox(
            width: 320,
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Theme.of(dialogContext).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SignaturePad(key: padKey, controller: padController),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            ListenableBuilder(
              listenable: padController,
              builder: (BuildContext context, Widget? _) => TextButton(
                onPressed: padController.isEmpty ? null : padController.clear,
                child: const Text('Clear'),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: padController,
                  builder: (BuildContext context, Widget? _) => FilledButton(
                    onPressed: padController.isEmpty
                        ? null
                        : () async {
                            final Uint8List? bytes = await padKey.currentState
                                ?.toPngBytes();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(bytes);
                            }
                          },
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (signature == null || !mounted) {
      return;
    }

    final int pageNumber = _controller.pageNumber > 0
        ? _controller.pageNumber
        : 1;
    final Uint8List? pageImage = await _controller.getPageThumbnail(
      pageNumber,
      width: 800,
    );
    if (pageImage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to preview this page for signing.'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final _ImagePlacement?
    placement = await showModalBottomSheet<_ImagePlacement>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _ImagePlacer(
        pageImage: pageImage,
        overlayImage: signature,
        title: 'Position your signature',
        instructions:
            'Drag the signature to move it, and use the slider to resize it.',
        confirmLabel: 'Place signature',
      ),
    );

    if (placement == null || !mounted) {
      return;
    }

    setState(() => _isSigning = true);

    try {
      final String sourcePath = await _resolvedPath;
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_sign',
      );
      final String outputPath = '${tempDir.path}/signed.pdf';

      final String? signedPath = await FlutterPdfToolkit.signPdf(
        sourcePath: sourcePath,
        outputPath: outputPath,
        signatureImageBytes: signature,
        pageNumber: pageNumber,
        xRatio: placement.xRatio,
        yRatio: placement.yRatio,
        widthRatio: placement.widthRatio,
        heightRatio: placement.heightRatio,
      );

      if (!mounted) {
        return;
      }

      if (signedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to sign the document.')),
        );
        return;
      }

      setState(() {
        _resolvedPath = Future.value(signedPath);
      });
      widget.onSigned?.call(signedPath);
    } finally {
      if (mounted) {
        setState(() => _isSigning = false);
      }
    }
  }

  Future<void> _startReorderFlow() async {
    final int pageCount = _controller.pageCount;
    if (pageCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This document needs at least 2 pages to reorder.'),
        ),
      );
      return;
    }

    final List<int>? newOrder = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _PageReorderSheet(
        pageCount: pageCount,
        thumbnailLoader: _loadThumbnail,
      ),
    );

    if (newOrder == null || !mounted) {
      return;
    }

    bool unchanged = true;
    for (int i = 0; i < newOrder.length; i++) {
      if (newOrder[i] != i + 1) {
        unchanged = false;
        break;
      }
    }
    if (unchanged) {
      return;
    }

    setState(() => _isReordering = true);

    try {
      final String sourcePath = await _resolvedPath;
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_reorder',
      );
      final String outputPath = '${tempDir.path}/reordered.pdf';

      final String? reorderedPath = await FlutterPdfToolkit.reorderPages(
        path: sourcePath,
        outputPath: outputPath,
        pageOrder: newOrder,
      );

      if (!mounted) {
        return;
      }

      if (reorderedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reorder pages.')),
        );
        return;
      }

      _thumbnailCache.clear();
      setState(() {
        _resolvedPath = Future.value(reorderedPath);
      });
      widget.onPagesReordered?.call(reorderedPath);
    } finally {
      if (mounted) {
        setState(() => _isReordering = false);
      }
    }
  }

  Future<void> _startDeletePagesFlow() async {
    final int pageCount = _controller.pageCount;
    if (pageCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This document needs at least 2 pages to delete pages.',
          ),
        ),
      );
      return;
    }

    final Set<int>? pagesToRemove = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _PageDeleteSheet(
        pageCount: pageCount,
        thumbnailLoader: _loadThumbnail,
      ),
    );

    if (pagesToRemove == null || pagesToRemove.isEmpty || !mounted) {
      return;
    }

    setState(() => _isDeletingPages = true);

    try {
      final String sourcePath = await _resolvedPath;
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_remove_pages',
      );
      final String outputPath = '${tempDir.path}/trimmed.pdf';

      final String? updatedPath = await FlutterPdfToolkit.removePages(
        path: sourcePath,
        outputPath: outputPath,
        pageNumbers: pagesToRemove.toList(),
      );

      if (!mounted) {
        return;
      }

      if (updatedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove pages.')),
        );
        return;
      }

      _thumbnailCache.clear();
      setState(() {
        _resolvedPath = Future.value(updatedPath);
      });
      widget.onPagesRemoved?.call(updatedPath);
    } finally {
      if (mounted) {
        setState(() => _isDeletingPages = false);
      }
    }
  }

  Future<void> _startAddPagesFlow() async {
    if (widget.onAddPagesRequested == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adding pages is not configured for this viewer.'),
        ),
      );
      return;
    }

    final int pageCount = _controller.pageCount;
    if (pageCount <= 0) {
      return;
    }

    final int? position = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _PageInsertPositionSheet(
        pageCount: pageCount,
        thumbnailLoader: _loadThumbnail,
      ),
    );

    if (position == null || !mounted) {
      return;
    }

    final List<String>? filesToInsert = await widget.onAddPagesRequested!
        .call();

    if (filesToInsert == null || filesToInsert.isEmpty || !mounted) {
      return;
    }

    setState(() => _isAddingPages = true);

    try {
      final String sourcePath = await _resolvedPath;
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_add_pages',
      );

      const Set<String> imageExtensions = {
        '.jpg',
        '.jpeg',
        '.png',
        '.heic',
        '.heif',
        '.webp',
        '.bmp',
        '.gif',
      };

      final List<String> insertParts = [];
      for (int i = 0; i < filesToInsert.length; i++) {
        final String filePath = filesToInsert[i];
        final int dotIndex = filePath.lastIndexOf('.');
        final String extension = dotIndex == -1
            ? ''
            : filePath.substring(dotIndex).toLowerCase();

        if (imageExtensions.contains(extension)) {
          final String imagePdfPath = '${tempDir.path}/image_$i.pdf';
          final String? converted = await FlutterPdfToolkit.imagesToPdf(
            imagePaths: [filePath],
            outputPath: imagePdfPath,
          );
          if (converted == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to add pages.')),
              );
            }
            return;
          }
          insertParts.add(converted);
        } else {
          insertParts.add(filePath);
        }
      }

      String insertPdfPath = insertParts.first;
      if (insertParts.length > 1) {
        final String? merged = await FlutterPdfToolkit.mergePdfs(
          paths: insertParts,
          outputPath: '${tempDir.path}/insert_combined.pdf',
        );
        if (merged == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to add pages.')),
            );
          }
          return;
        }
        insertPdfPath = merged;
      }

      final String outputPath = '${tempDir.path}/with_added_pages.pdf';
      final String? updatedPath = await FlutterPdfToolkit.insertPages(
        path: sourcePath,
        insertPath: insertPdfPath,
        outputPath: outputPath,
        afterPageNumber: position,
      );

      if (!mounted) {
        return;
      }

      if (updatedPath == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add pages.')));
        return;
      }

      _thumbnailCache.clear();
      setState(() {
        _resolvedPath = Future.value(updatedPath);
      });
      widget.onPagesAdded?.call(updatedPath);
    } finally {
      if (mounted) {
        setState(() => _isAddingPages = false);
      }
    }
  }

  Future<void> _startAddImageFlow() async {
    if (widget.onAddImageRequested == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adding images is not configured for this viewer.'),
        ),
      );
      return;
    }

    final Uint8List? image = await widget.onAddImageRequested!.call();

    if (image == null || !mounted) {
      return;
    }

    final int pageNumber = _controller.pageNumber > 0
        ? _controller.pageNumber
        : 1;
    final Uint8List? pageImage = await _controller.getPageThumbnail(
      pageNumber,
      width: 800,
    );
    if (pageImage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to preview this page for placing the image.'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final _ImagePlacement? placement =
        await showModalBottomSheet<_ImagePlacement>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) => _ImagePlacer(
            pageImage: pageImage,
            overlayImage: image,
            title: 'Position your image',
            instructions:
                'Drag the image to move it, and use the slider to resize it.',
            confirmLabel: 'Place image',
          ),
        );

    if (placement == null || !mounted) {
      return;
    }

    setState(() => _isAddingImage = true);

    try {
      final String sourcePath = await _resolvedPath;
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_add_image',
      );
      final String outputPath = '${tempDir.path}/with_image.pdf';

      final String? updatedPath = await FlutterPdfToolkit.addImageToPdf(
        sourcePath: sourcePath,
        outputPath: outputPath,
        imageBytes: image,
        pageNumber: pageNumber,
        xRatio: placement.xRatio,
        yRatio: placement.yRatio,
        widthRatio: placement.widthRatio,
        heightRatio: placement.heightRatio,
      );

      if (!mounted) {
        return;
      }

      if (updatedPath == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add image.')));
        return;
      }

      _thumbnailCache.clear();
      setState(() {
        _resolvedPath = Future.value(updatedPath);
      });
      widget.onImageAdded?.call(updatedPath);
    } finally {
      if (mounted) {
        setState(() => _isAddingImage = false);
      }
    }
  }

  Widget _buildToolbar(BuildContext context) {
    final Color foreground =
        widget.toolbarForegroundColor ??
        Theme.of(context).colorScheme.onSurface;
    final Color background =
        widget.toolbarBackgroundColor ?? Theme.of(context).colorScheme.surface;

    final String? searchText = _controller.searchText;
    final bool hasSearchText = searchText != null && searchText.isNotEmpty;
    final bool isSearching = _controller.isSearching;

    return Material(
      color: background,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: hasSearchText
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  child: Row(
                    children: [
                      if (isSearching)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.search,
                          color: foreground.withAlpha((0.7 * 255).round()),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        isSearching
                            ? 'Searching for "$searchText"...'
                            : 'Results for "$searchText"',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!isSearching) ...[
                        if (_controller.searchResultCount > 0) ...[
                          _ToolbarChip(
                            label:
                                '${_controller.currentSearchResultIndex}/${_controller.searchResultCount}',
                            color: foreground,
                          ),
                          IconButton(
                            tooltip: 'Previous result',
                            color: foreground,
                            onPressed: _controller.previousSearchResult,
                            icon: const Icon(Icons.keyboard_arrow_left),
                          ),
                          IconButton(
                            tooltip: 'Next result',
                            color: foreground,
                            onPressed: _controller.nextSearchResult,
                            icon: const Icon(Icons.keyboard_arrow_right),
                          ),
                        ] else ...[
                          _ToolbarChip(label: 'No results', color: foreground),
                        ],
                      ],
                      if (widget.showZoomControls) ...[
                        IconButton(
                          tooltip: 'Zoom out',
                          color: foreground,
                          onPressed: _controller.zoomOut,
                          icon: const Icon(Icons.zoom_out),
                        ),
                        IconButton(
                          tooltip: 'Zoom in',
                          color: foreground,
                          onPressed: _controller.zoomIn,
                          icon: const Icon(Icons.zoom_in),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Clear search',
                        color: foreground,
                        onPressed: _controller.clearSearch,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      if (widget.showPageControls) ...[
                        IconButton(
                          tooltip: 'Previous page',
                          color: foreground,
                          onPressed: _controller.previousPage,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        _ToolbarChip(
                          label:
                              '${_controller.pageNumber}/${_controller.pageCount}',
                          color: foreground,
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          color: foreground,
                          onPressed: _controller.nextPage,
                          icon: const Icon(Icons.chevron_right),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.showZoomControls) ...[
                        IconButton(
                          tooltip: 'Zoom out',
                          color: foreground,
                          onPressed: _controller.zoomOut,
                          icon: const Icon(Icons.zoom_out),
                        ),
                        _ToolbarChip(
                          label: '${_controller.zoomLevel.toStringAsFixed(1)}x',
                          color: foreground,
                        ),
                        IconButton(
                          tooltip: 'Zoom in',
                          color: foreground,
                          onPressed: _controller.zoomIn,
                          icon: const Icon(Icons.zoom_in),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.showSearch)
                        isSearching
                            ? IconButton(
                                tooltip: 'Searching...',
                                color: foreground,
                                onPressed: null,
                                icon: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Search',
                                color: foreground,
                                onPressed: _showSearchDialog,
                                icon: const Icon(Icons.search),
                              ),
                      if (widget.showBookmarks)
                        IconButton(
                          tooltip: 'Bookmarks',
                          color: foreground,
                          onPressed: _showBookmarks,
                          icon: const Icon(Icons.bookmark_outline),
                        ),
                      if (widget.showThumbnails)
                        IconButton(
                          tooltip: 'Pages',
                          color: foreground,
                          onPressed: _showThumbnails,
                          icon: const Icon(Icons.grid_view_rounded),
                        ),
                      if (widget.showSignature)
                        IconButton(
                          tooltip: 'Sign document',
                          color: foreground,
                          onPressed: _isSigning ? null : _startSignFlow,
                          icon: _isSigning
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : const Icon(Icons.draw_outlined),
                        ),
                      if (widget.showReorder)
                        IconButton(
                          tooltip: 'Reorder pages',
                          color: foreground,
                          onPressed: _isReordering ? null : _startReorderFlow,
                          icon: _isReordering
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : const Icon(Icons.swap_vert_circle_outlined),
                        ),
                      if (widget.showDeletePages)
                        IconButton(
                          tooltip: 'Delete pages',
                          color: foreground,
                          onPressed: _isDeletingPages
                              ? null
                              : _startDeletePagesFlow,
                          icon: _isDeletingPages
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                      if (widget.showAddPages)
                        IconButton(
                          tooltip: 'Add pages',
                          color: foreground,
                          onPressed: _isAddingPages ? null : _startAddPagesFlow,
                          icon: _isAddingPages
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : const Icon(Icons.note_add_outlined),
                        ),
                      if (widget.showAddImage)
                        IconButton(
                          tooltip: 'Add image',
                          color: foreground,
                          onPressed: _isAddingImage ? null : _startAddImageFlow,
                          icon: _isAddingImage
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined),
                        ),
                      if (widget.showThemeToggle)
                        IconButton(
                          tooltip: 'Toggle theme',
                          color: foreground,
                          onPressed: () {
                            setState(() => _darkMode = !_darkMode);
                            _controller.setDarkMode(_darkMode);
                          },
                          icon: Icon(
                            _darkMode ? Icons.light_mode : Icons.dark_mode,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildNativeView(String path) {
    final String? password =
        widget.password ??
        (widget.source is Base64PdfSource
            ? (widget.source as Base64PdfSource).password
            : null);
    final Map<String, dynamic> params = <String, dynamic>{
      'path': path,
      'initialZoomLevel': widget.initialZoomLevel,
      'initialPage': widget.initialPage,
      'password': password,
      'scrollDirection': widget.scrollDirection == Axis.horizontal
          ? 'horizontal'
          : 'vertical',
      'singlePage': widget.singlePage,
      'darkMode': _darkMode,
    };

    final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers =
        <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
          Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
        };

    final Widget view = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            key: ValueKey(path),
            viewType: 'flutter_pdf_toolkit/native_view',
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _attachChannel,
            gestureRecognizers: gestureRecognizers,
          )
        : AndroidView(
            key: ValueKey(path),
            viewType: 'flutter_pdf_toolkit/native_view',
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _attachChannel,
            gestureRecognizers: gestureRecognizers,
          );

    return ColoredBox(
      color:
          widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: view,
    );
  }

  Future<String?> _handlePasswordRequired(bool retry) async {
    final TextEditingController passwordController = TextEditingController();
    bool obscureText = true;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              icon: Icon(
                Icons.lock_outline,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Password Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This PDF file is encrypted and requires a password to open.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscureText,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter PDF password',
                      errorText: retry ? 'Incorrect password' : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            obscureText = !obscureText;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (String val) {
                      Navigator.of(dialogContext).pop(val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(passwordController.text);
                  },
                  child: const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.errorMessage != null) {
      return ColoredBox(
        color:
            widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _controller.errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _resolvedPath,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Text(
              'Failed to load PDF source',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }

        return Stack(
          children: [
            Column(
              children: [
                if (widget.showToolbar) _buildToolbar(context),
                Expanded(child: _buildNativeView(snapshot.data!)),
              ],
            ),
            if (_controller.isSearching)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withAlpha((0.3 * 255).round()),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.2 * 255).round()),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Searching...',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This may take a moment',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha((0.08 * 255).round()),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

/// The placement chosen for an image stamp, as fractions of the target
/// page's width/height (see [FlutterPdfToolkit.signPdf] and
/// [FlutterPdfToolkit.addImageToPdf]).
class _ImagePlacement {
  const _ImagePlacement({
    required this.xRatio,
    required this.yRatio,
    required this.widthRatio,
    required this.heightRatio,
  });

  final double xRatio;
  final double yRatio;
  final double widthRatio;
  final double heightRatio;
}

/// Lets the user drag and resize an overlay image on top of a preview of
/// the current PDF page, producing an [_ImagePlacement].
class _ImagePlacer extends StatefulWidget {
  const _ImagePlacer({
    required this.pageImage,
    required this.overlayImage,
    required this.title,
    required this.instructions,
    required this.confirmLabel,
  });

  final Uint8List pageImage;
  final Uint8List overlayImage;
  final String title;
  final String instructions;
  final String confirmLabel;

  @override
  State<_ImagePlacer> createState() => _ImagePlacerState();
}

class _ImagePlacerState extends State<_ImagePlacer> {
  double? _pageAspectRatio;
  double? _overlayAspectRatio;
  double _left = 0.3;
  double _top = 0.75;
  double _width = 0.35;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAspectRatios());
  }

  Future<void> _loadAspectRatios() async {
    final Size pageSize = await _decodeSize(widget.pageImage);
    final Size overlaySize = await _decodeSize(widget.overlayImage);
    if (!mounted) {
      return;
    }
    setState(() {
      _pageAspectRatio = pageSize.width / pageSize.height;
      _overlayAspectRatio = overlaySize.width / overlaySize.height;
    });
  }

  Future<Size> _decodeSize(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final Size size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final double? pageAspect = _pageAspectRatio;
    final double? overlayAspect = _overlayAspectRatio;

    double left = 0;
    double top = 0;
    double heightRatio = 0;
    double maxLeft = 1;
    double maxTop = 1;
    if (pageAspect != null && overlayAspect != null) {
      heightRatio = (_width * pageAspect / overlayAspect).clamp(0.02, 1.0);
      maxLeft = (1.0 - _width).clamp(0.0, 1.0);
      maxTop = (1.0 - heightRatio).clamp(0.0, 1.0);
      left = _left.clamp(0.0, maxLeft);
      top = _top.clamp(0.0, maxTop);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.instructions,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (pageAspect == null || overlayAspect == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double boxWidth = constraints.maxWidth;
                  final double boxHeight = boxWidth / pageAspect;

                  return ClipRect(
                    child: SizedBox(
                      width: boxWidth,
                      height: boxHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(
                              widget.pageImage,
                              fit: BoxFit.fill,
                            ),
                          ),
                          Positioned(
                            left: left * boxWidth,
                            top: top * boxHeight,
                            width: _width * boxWidth,
                            height: heightRatio * boxHeight,
                            child: GestureDetector(
                              onPanUpdate: (DragUpdateDetails details) {
                                setState(() {
                                  _left = (left + details.delta.dx / boxWidth)
                                      .clamp(0.0, maxLeft);
                                  _top = (top + details.delta.dy / boxHeight)
                                      .clamp(0.0, maxTop);
                                });
                              },
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                                child: Image.memory(
                                  widget.overlayImage,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.photo_size_select_small),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 0.1,
                    max: 0.8,
                    onChanged: (double value) => setState(() => _width = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (pageAspect == null || overlayAspect == null)
                        ? null
                        : () => Navigator.of(context).pop(
                            _ImagePlacement(
                              xRatio: left,
                              yRatio: top,
                              widthRatio: _width,
                              heightRatio: heightRatio,
                            ),
                          ),
                    child: Text(widget.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user drag page thumbnails into a new order, returning the
/// reordered list of 1-based page numbers when the user taps "Save order".
class _PageReorderSheet extends StatefulWidget {
  const _PageReorderSheet({
    required this.pageCount,
    required this.thumbnailLoader,
  });

  final int pageCount;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;

  @override
  State<_PageReorderSheet> createState() => _PageReorderSheetState();
}

class _PageReorderSheetState extends State<_PageReorderSheet> {
  late List<int> _order;

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(widget.pageCount, (int index) => index + 1);
  }

  void _movePage(int from, int to) {
    if (from == to) {
      return;
    }
    setState(() {
      final int page = _order.removeAt(from);
      _order.insert(to, page);
    });
  }

  bool get _isReordered {
    for (int i = 0; i < _order.length; i++) {
      if (_order[i] != i + 1) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reorder pages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Press and hold a page, then drag it to a new position.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: _order.length,
                itemBuilder: (BuildContext context, int index) {
                  final int pageNumber = _order[index];
                  final Widget tile = _PageTile(
                    pageNumber: pageNumber,
                    position: index + 1,
                    thumbnailLoader: widget.thumbnailLoader,
                  );

                  return DragTarget<int>(
                    onWillAcceptWithDetails: (DragTargetDetails<int> details) =>
                        details.data != index,
                    onAcceptWithDetails: (DragTargetDetails<int> details) =>
                        _movePage(details.data, index),
                    builder:
                        (
                          BuildContext context,
                          List<int?> candidateData,
                          List<dynamic> rejectedData,
                        ) {
                          return AnimatedScale(
                            scale: candidateData.isNotEmpty ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: LongPressDraggable<int>(
                              data: index,
                              feedback: SizedBox(
                                width: 100,
                                height: 125,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(16),
                                  child: tile,
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: tile,
                              ),
                              child: tile,
                            ),
                          );
                        },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isReordered
                          ? () => Navigator.of(context).pop(_order)
                          : null,
                      child: const Text('Save order'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single draggable page tile used by [_PageReorderSheet], showing the
/// page's thumbnail, its original page number, and its current position.
class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.pageNumber,
    required this.position,
    required this.thumbnailLoader,
  });

  final int pageNumber;
  final int position;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: thumbnailLoader(pageNumber),
            builder:
                (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final Uint8List? data = snapshot.data;
                  if (data == null) {
                    return Center(child: Text('Page $pageNumber'));
                  }
                  return Image.memory(data, fit: BoxFit.cover);
                },
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha((0.55 * 255).round()),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Page $pageNumber',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$position',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Icon(
              Icons.drag_indicator,
              color: Colors.white.withAlpha((0.85 * 255).round()),
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the user tap page thumbnails to mark them for removal, returning the
/// set of 1-based page numbers to delete when the user confirms.
class _PageDeleteSheet extends StatefulWidget {
  const _PageDeleteSheet({
    required this.pageCount,
    required this.thumbnailLoader,
  });

  final int pageCount;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;

  @override
  State<_PageDeleteSheet> createState() => _PageDeleteSheetState();
}

class _PageDeleteSheetState extends State<_PageDeleteSheet> {
  final Set<int> _selectedPages = {};

  void _toggle(int pageNumber) {
    setState(() {
      if (!_selectedPages.remove(pageNumber)) {
        _selectedPages.add(pageNumber);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool canDelete =
        _selectedPages.isNotEmpty && _selectedPages.length < widget.pageCount;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete pages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap pages to mark them for removal.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: widget.pageCount,
                itemBuilder: (BuildContext context, int index) {
                  final int pageNumber = index + 1;
                  return _DeletablePageTile(
                    pageNumber: pageNumber,
                    selected: _selectedPages.contains(pageNumber),
                    thumbnailLoader: widget.thumbnailLoader,
                    onTap: () => _toggle(pageNumber),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canDelete
                          ? () => Navigator.of(context).pop(_selectedPages)
                          : null,
                      child: Text(
                        _selectedPages.isEmpty
                            ? 'Delete'
                            : 'Delete ${_selectedPages.length} page${_selectedPages.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single selectable page tile used by [_PageDeleteSheet], showing the
/// page's thumbnail, its page number, and whether it's marked for removal.
class _DeletablePageTile extends StatelessWidget {
  const _DeletablePageTile({
    required this.pageNumber,
    required this.selected,
    required this.thumbnailLoader,
    required this.onTap,
  });

  final int pageNumber;
  final bool selected;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbnailLoader(pageNumber),
              builder:
                  (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final Uint8List? data = snapshot.data;
                    if (data == null) {
                      return Center(child: Text('Page $pageNumber'));
                    }
                    return Image.memory(data, fit: BoxFit.cover);
                  },
            ),
            if (selected)
              ColoredBox(color: primary.withAlpha((0.35 * 255).round())),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.55 * 255).round()),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Page $pageNumber',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? primary
                      : Colors.black.withAlpha((0.35 * 255).round()),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha((0.85 * 255).round()),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user pick where newly-added pages should be inserted, returning
/// the 1-based page number to insert the new pages after (or `0` to insert
/// them before the first page) when the user confirms.
class _PageInsertPositionSheet extends StatefulWidget {
  const _PageInsertPositionSheet({
    required this.pageCount,
    required this.thumbnailLoader,
  });

  final int pageCount;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;

  @override
  State<_PageInsertPositionSheet> createState() =>
      _PageInsertPositionSheetState();
}

class _PageInsertPositionSheetState extends State<_PageInsertPositionSheet> {
  late int _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.pageCount;
  }

  String get _confirmLabel {
    if (_selectedPosition == 0) {
      return 'Add at the start';
    }
    if (_selectedPosition == widget.pageCount) {
      return 'Add at the end';
    }
    return 'Add after page $_selectedPosition';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add pages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose where the new pages should be inserted.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: widget.pageCount + 1,
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return _InsertPositionTile(
                      label: 'Start',
                      icon: Icons.first_page,
                      selected: _selectedPosition == 0,
                      onTap: () => setState(() => _selectedPosition = 0),
                    );
                  }
                  final int pageNumber = index;
                  return _InsertablePageTile(
                    pageNumber: pageNumber,
                    selected: _selectedPosition == pageNumber,
                    thumbnailLoader: widget.thumbnailLoader,
                    onTap: () => setState(() => _selectedPosition = pageNumber),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selectedPosition),
                      child: Text(_confirmLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The leading tile in [_PageInsertPositionSheet], representing inserting
/// the new pages before the first page of the document.
class _InsertPositionTile extends StatelessWidget {
  const _InsertPositionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: selected
                        ? primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? primary
                      : Colors.black.withAlpha((0.35 * 255).round()),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha((0.85 * 255).round()),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  selected ? Icons.check : Icons.add,
                  size: 16,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single selectable page tile used by [_PageInsertPositionSheet], showing
/// the page's thumbnail and whether the new pages will be inserted after it.
class _InsertablePageTile extends StatelessWidget {
  const _InsertablePageTile({
    required this.pageNumber,
    required this.selected,
    required this.thumbnailLoader,
    required this.onTap,
  });

  final int pageNumber;
  final bool selected;
  final Future<Uint8List?> Function(int pageNumber) thumbnailLoader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbnailLoader(pageNumber),
              builder:
                  (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final Uint8List? data = snapshot.data;
                    if (data == null) {
                      return Center(child: Text('Page $pageNumber'));
                    }
                    return Image.memory(data, fit: BoxFit.cover);
                  },
            ),
            if (selected)
              ColoredBox(color: primary.withAlpha((0.35 * 255).round())),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.55 * 255).round()),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Page $pageNumber',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? primary
                      : Colors.black.withAlpha((0.35 * 255).round()),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha((0.85 * 255).round()),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  selected ? Icons.check : Icons.add,
                  size: 16,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
