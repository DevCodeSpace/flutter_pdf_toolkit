import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_pdf_toolkit/flutter_pdf_toolkit.dart';

@Preview(name: 'My Sample Text')
Widget mySampleText() {
  return const PdfProExampleApp();
}

void main() {
  runApp(const PdfProExampleApp());
}

class PdfProExampleApp extends StatelessWidget {
  const PdfProExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter PDF Pro',
      theme: ThemeData(useMaterial3: true),
      home: const PdfProExampleHome(),
    );
  }
}

enum DemoSourceKind {
  asset,
  network,
  googleDrive,
  bytes,
  base64,
  filePath,
  merge,
  split,
}

class PdfProExampleHome extends StatefulWidget {
  const PdfProExampleHome({super.key});

  @override
  State<PdfProExampleHome> createState() => _PdfProExampleHomeState();
}

class _PdfProExampleHomeState extends State<PdfProExampleHome> {
  static const String _googleDrivePdfUrl =
      'https://drive.google.com/file/d/1oPlPnK88iwL96GEF0_2kkR0S2DpN-oLT/view';

  final FlutterPdfToolkitController _controller = FlutterPdfToolkitController();
  DemoSourceKind _kind = DemoSourceKind.filePath;
  bool _darkMode = false;
  Uint8List? _networkBytes;
  String? _tempFilePath;

  // Merge state
  String? _mergedFilePath;
  bool _isMerging = false;

  // Split state
  List<String>? _splitFilePaths;
  int _selectedSplitIndex = 0;
  bool _isSplitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSamplePdf());
  }

  Future<void> _loadSamplePdf() async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        'https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf',
      ),
    );
    final HttpClientResponse response = await request.close();
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      bytes.add(chunk);
    }
    client.close(force: true);
    final Uint8List pdfBytes = bytes.takeBytes();
    final Directory dir = await Directory.systemTemp.createTemp(
      'flutter_pdf_toolkit_example',
    );
    final File file = File('${dir.path}/sample.pdf');
    await file.writeAsBytes(pdfBytes, flush: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _networkBytes = pdfBytes;
      _tempFilePath = file.path;
    });
  }

  Future<void> _performMerge() async {
    setState(() {
      _isMerging = true;
      _mergedFilePath = null;
    });

    try {
      final Directory dir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_merge',
      );

      // Copy assets/sample.pdf to a temp file
      final File file1 = File('${dir.path}/sample_asset.pdf');
      final ByteData data = await rootBundle.load('assets/sample.pdf');
      await file1.writeAsBytes(data.buffer.asUint8List(), flush: true);

      // Copy assets/sample.pdf or use downloaded pdf as the second file
      final File file2 = File('${dir.path}/doc2.pdf');
      if (_networkBytes != null) {
        await file2.writeAsBytes(_networkBytes!, flush: true);
      } else {
        await file2.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }

      final String outputPath = '${dir.path}/merged_output.pdf';
      final String? resultPath = await FlutterPdfToolkit.mergePdfs(
        paths: [file1.path, file2.path],
        outputPath: outputPath,
      );

      setState(() {
        _mergedFilePath = resultPath;
        _isMerging = false;
      });
    } catch (e) {
      setState(() {
        _isMerging = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Merge failed: $e')));
      }
    }
  }

  Future<void> _performSplit() async {
    setState(() {
      _isSplitting = true;
      _splitFilePaths = null;
      _selectedSplitIndex = 0;
    });

    try {
      final Directory dir = await Directory.systemTemp.createTemp(
        'flutter_pdf_toolkit_split',
      );

      // Copy assets/sample.pdf to a temp file
      final File assetFile = File('${dir.path}/sample.pdf');
      final ByteData data = await rootBundle.load('assets/sample.pdf');
      await assetFile.writeAsBytes(data.buffer.asUint8List(), flush: true);

      // assets/sample.pdf only has a single page, so build a multi-page source
      // for the split demo by merging a few copies of it together.
      final File sourceFile = File('${dir.path}/split_source.pdf');
      final String? mergedPath = await FlutterPdfToolkit.mergePdfs(
        paths: [assetFile.path, assetFile.path, assetFile.path, assetFile.path],
        outputPath: sourceFile.path,
      );
      if (mergedPath == null) {
        throw Exception('Failed to prepare a multi-page PDF for splitting');
      }

      final int? pageCount = await FlutterPdfToolkit.getPdfPageCount(
        sourceFile.path,
      );
      if (pageCount == null || pageCount < 2) {
        throw Exception('Source PDF does not have enough pages to split');
      }

      // Split the document roughly in half.
      final int firstHalfEnd = (pageCount / 2).ceil();
      final List<String>? results = await FlutterPdfToolkit.splitPdf(
        path: sourceFile.path,
        outputDirectory: '${dir.path}/split_output',
        pageRanges: [
          [1, firstHalfEnd],
          [firstHalfEnd + 1, pageCount],
        ],
      );

      setState(() {
        _splitFilePaths = results;
        _isSplitting = false;
      });
    } catch (e) {
      setState(() {
        _isSplitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Split failed: $e')));
      }
    }
  }

  Future<void> _downloadSplitPdf() async {
    final List<String>? paths = _splitFilePaths;
    if (paths == null || paths.isEmpty) return;
    final String sourcePath = paths[_selectedSplitIndex];
    final success = await FlutterPdfToolkit.downloadPdf(
      sourcePath: sourcePath,
      fileName: 'split_part_${_selectedSplitIndex + 1}.pdf',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (Platform.isIOS
                      ? 'Share sheet opened successfully!'
                      : 'PDF saved to Downloads folder!')
                : 'Failed to download PDF.',
          ),
        ),
      );
    }
  }

  Future<void> _downloadMergedPdf() async {
    if (_mergedFilePath == null) return;
    final success = await FlutterPdfToolkit.downloadPdf(
      sourcePath: _mergedFilePath!,
      fileName: 'merged_document.pdf',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (Platform.isIOS
                      ? 'Share sheet opened successfully!'
                      : 'PDF saved to Downloads folder!')
                : 'Failed to download PDF.',
          ),
        ),
      );
    }
  }

  void _onSigned(String signedFilePath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Document signed!'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () async {
            final success = await FlutterPdfToolkit.downloadPdf(
              sourcePath: signedFilePath,
              fileName: 'signed_document.pdf',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (Platform.isIOS
                              ? 'Share sheet opened successfully!'
                              : 'PDF saved to Downloads folder!')
                        : 'Failed to download PDF.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _onPagesReordered(String reorderedFilePath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pages reordered!'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () async {
            final success = await FlutterPdfToolkit.downloadPdf(
              sourcePath: reorderedFilePath,
              fileName: 'reordered_document.pdf',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (Platform.isIOS
                              ? 'Share sheet opened successfully!'
                              : 'PDF saved to Downloads folder!')
                        : 'Failed to download PDF.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  /// Demo implementation of [FlutterPdfToolkit.onAddPagesRequested]. Real
  /// apps would show a file/image picker here; this demo simply offers the
  /// bundled sample PDF as the file to insert.
  Future<List<String>?> _onAddPagesRequested() async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'flutter_pdf_toolkit_add_pages',
    );
    final File file = File('${dir.path}/sample_to_insert.pdf');
    final ByteData data = await rootBundle.load('assets/sample.pdf');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return [file.path];
  }

  void _onPagesAdded(String updatedFilePath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pages added!'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () async {
            final success = await FlutterPdfToolkit.downloadPdf(
              sourcePath: updatedFilePath,
              fileName: 'updated_document.pdf',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (Platform.isIOS
                              ? 'Share sheet opened successfully!'
                              : 'PDF saved to Downloads folder!')
                        : 'Failed to download PDF.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _onPagesRemoved(String updatedFilePath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pages removed!'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () async {
            final success = await FlutterPdfToolkit.downloadPdf(
              sourcePath: updatedFilePath,
              fileName: 'trimmed_document.pdf',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (Platform.isIOS
                              ? 'Share sheet opened successfully!'
                              : 'PDF saved to Downloads folder!')
                        : 'Failed to download PDF.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  /// Demo implementation of [FlutterPdfToolkit.onAddImageRequested]. Real
  /// apps would show an image picker here (e.g. via the `image_picker`
  /// package); this demo draws a simple "stamp" image on the fly.
  Future<Uint8List?> _onAddImageRequested() async {
    const double size = 240;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, size, size),
    );

    final Paint fillPaint = Paint()..color = const Color(0xFF2563EB);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, size, size),
        const Radius.circular(24),
      ),
      fillPaint,
    );

    final TextPainter textPainter = TextPainter(
      text: const TextSpan(
        text: 'LOGO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 56,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  void _onImageAdded(String updatedFilePath) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Image added!'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () async {
            final success = await FlutterPdfToolkit.downloadPdf(
              sourcePath: updatedFilePath,
              fileName: 'image_document.pdf',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? (Platform.isIOS
                              ? 'Share sheet opened successfully!'
                              : 'PDF saved to Downloads folder!')
                        : 'Failed to download PDF.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  PdfSource? get _source {
    switch (_kind) {
      case DemoSourceKind.asset:
        return const PdfSource.asset('assets/protected.pdf');
      case DemoSourceKind.network:
        return const PdfSource.network(
          'https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf',
        );
      case DemoSourceKind.googleDrive:
        return const PdfSource.network(_googleDrivePdfUrl);
      case DemoSourceKind.bytes:
        return _networkBytes == null ? null : PdfSource.bytes(_networkBytes!);
      case DemoSourceKind.base64:
        return _networkBytes == null
            ? null
            : PdfSource.base64(base64Encode(_networkBytes!));
      case DemoSourceKind.filePath:
        return _tempFilePath == null
            ? null
            : PdfSource.filePath(_tempFilePath!);
      case DemoSourceKind.merge:
        return _mergedFilePath == null
            ? null
            : PdfSource.filePath(_mergedFilePath!);
      case DemoSourceKind.split:
        final List<String>? paths = _splitFilePaths;
        if (paths == null || paths.isEmpty) return null;
        return PdfSource.filePath(paths[_selectedSplitIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PdfSource? source = _source;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter PDF Pro'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _darkMode = !_darkMode),
            icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Asset'),
                  selected: _kind == DemoSourceKind.asset,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.asset),
                ),
                ChoiceChip(
                  label: const Text('Network'),
                  selected: _kind == DemoSourceKind.network,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.network),
                ),
                ChoiceChip(
                  label: const Text('Google Drive'),
                  selected: _kind == DemoSourceKind.googleDrive,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.googleDrive),
                ),
                ChoiceChip(
                  label: const Text('Bytes'),
                  selected: _kind == DemoSourceKind.bytes,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.bytes),
                ),
                ChoiceChip(
                  label: const Text('Base64'),
                  selected: _kind == DemoSourceKind.base64,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.base64),
                ),
                ChoiceChip(
                  label: const Text('File'),
                  selected: _kind == DemoSourceKind.filePath,
                  onSelected: (_) =>
                      setState(() => _kind = DemoSourceKind.filePath),
                ),
                ChoiceChip(
                  label: const Text('Merge PDFs'),
                  selected: _kind == DemoSourceKind.merge,
                  onSelected: (_) {
                    setState(() => _kind = DemoSourceKind.merge);
                    if (_mergedFilePath == null && !_isMerging) {
                      _performMerge();
                    }
                  },
                ),
                ChoiceChip(
                  label: const Text('Split PDF'),
                  selected: _kind == DemoSourceKind.split,
                  onSelected: (_) {
                    setState(() => _kind = DemoSourceKind.split);
                    if (_splitFilePaths == null && !_isSplitting) {
                      _performSplit();
                    }
                  },
                ),
              ],
            ),
          ),

          if (_kind == DemoSourceKind.split &&
              (_splitFilePaths?.length ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (int i = 0; i < _splitFilePaths!.length; i++)
                    ChoiceChip(
                      label: Text('Part ${i + 1}'),
                      selected: _selectedSplitIndex == i,
                      onSelected: (_) =>
                          setState(() => _selectedSplitIndex = i),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _darkMode ? const Color(0xFF0F172A) : Colors.white,
                    border: Border.all(color: Colors.black12),
                  ),
                  child: _isMerging
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Merging PDFs, please wait...'),
                            ],
                          ),
                        )
                      : _isSplitting
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Splitting PDF, please wait...'),
                            ],
                          ),
                        )
                      : (source == null
                            ? const Center(child: CircularProgressIndicator())
                            : FlutterPdfToolkit(
                                key: ValueKey(
                                  '${_kind}_${_mergedFilePath ?? ""}_${_splitFilePaths?.join(",") ?? ""}_$_selectedSplitIndex',
                                ),
                                source: source,
                                controller: _controller,
                                darkMode: _darkMode,
                                onSigned: _onSigned,
                                onPagesReordered: _onPagesReordered,
                                onPagesRemoved: _onPagesRemoved,
                                onAddPagesRequested: _onAddPagesRequested,
                                onPagesAdded: _onPagesAdded,
                                onAddImageRequested: _onAddImageRequested,
                                onImageAdded: _onImageAdded,
                              )),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          _kind == DemoSourceKind.merge && _mergedFilePath != null
          ? FloatingActionButton.extended(
              onPressed: _downloadMergedPdf,
              label: const Text('Download PDF'),
              icon: const Icon(Icons.download),
            )
          : _kind == DemoSourceKind.split &&
                (_splitFilePaths?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: _downloadSplitPdf,
              label: const Text('Download part'),
              icon: const Icon(Icons.download),
            )
          : null,
    );
  }
}
