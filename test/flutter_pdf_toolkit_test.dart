import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pdf_toolkit/flutter_pdf_toolkit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes base64 PDF payloads', () {
    const String payload = 'data:application/pdf;base64,SGVsbG8=';
    final PdfSource source = PdfSource.base64(payload);

    expect(source, isA<Base64PdfSource>());
    expect(
      (source as Base64PdfSource).bytes,
      Uint8List.fromList(utf8.encode('Hello')),
    );
  });

  test('normalizes Google Drive network PDF URLs', () {
    final NetworkPdfSource driveSource =
        const PdfSource.network(
              'https://drive.google.com/file/d/1a2B3cD4e5F6g7H8I9J0/view?usp=sharing',
            )
            as NetworkPdfSource;
    final NetworkPdfSource openSource =
        const PdfSource.network(
              'https://drive.google.com/open?id=1a2B3cD4e5F6g7H8I9J0',
            )
            as NetworkPdfSource;
    final NetworkPdfSource ucSource =
        const PdfSource.network(
              'https://drive.google.com/uc?export=download&id=1a2B3cD4e5F6g7H8I9J0',
            )
            as NetworkPdfSource;

    expect(
      normalizeNetworkPdfUrl(Uri.parse(driveSource.url)),
      Uri.https('drive.google.com', '/uc', {
        'export': 'download',
        'id': '1a2B3cD4e5F6g7H8I9J0',
      }),
    );

    expect(
      normalizeNetworkPdfUrl(Uri.parse(openSource.url)),
      Uri.https('drive.google.com', '/uc', {
        'export': 'download',
        'id': '1a2B3cD4e5F6g7H8I9J0',
      }),
    );

    expect(
      normalizeNetworkPdfUrl(Uri.parse(ucSource.url)),
      Uri.https('drive.google.com', '/uc', {
        'export': 'download',
        'id': '1a2B3cD4e5F6g7H8I9J0',
      }),
    );
  });

  test('network PDF downloads are cached by URL', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'flutter_pdf_toolkit_test',
    );
    addTearDown(() async {
      await tempDir.delete(recursive: true);
      NetworkPdfSource.debugDownloadOverride = null;
    });

    int downloadCount = 0;
    final Uint8List payload = Uint8List.fromList(
      utf8.encode('%PDF-1.4\n%fake\n'),
    );
    final File file = File('${tempDir.path}/downloaded.pdf');
    await file.writeAsBytes(payload, flush: true);

    NetworkPdfSource.debugDownloadOverride =
        (Uri uri, Map<String, String>? headers) async {
          downloadCount++;
          return file.path;
        };

    final PdfSource source = PdfSource.network(
      'https://drive.google.com/file/d/1a2B3cD4e5F6g7H8I9J0/view?usp=sharing',
    );

    final String firstPath = await source.resolveToFile();
    final String secondPath = await source.resolveToFile();

    expect(firstPath, file.path);
    expect(secondPath, file.path);
    expect(downloadCount, 1);
  });

  group('FlutterPdfToolkit Static Methods', () {
    const MethodChannel channel = MethodChannel('flutter_pdf_toolkit');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            if (methodCall.method == 'mergePdfs') {
              return '/path/to/merged.pdf';
            } else if (methodCall.method == 'downloadPdf') {
              return true;
            } else if (methodCall.method == 'reorderPdf') {
              return '/path/to/reordered.pdf';
            }
            return null;
          });
      log.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('mergePdfs invokes method channel', () async {
      final result = await FlutterPdfToolkit.mergePdfs(
        paths: ['/path/1.pdf', '/path/2.pdf'],
        outputPath: '/path/out.pdf',
      );

      expect(result, '/path/to/merged.pdf');
      expect(log, hasLength(1));
      expect(log.first.method, 'mergePdfs');
      expect(log.first.arguments, <String, dynamic>{
        'paths': ['/path/1.pdf', '/path/2.pdf'],
        'outputPath': '/path/out.pdf',
      });
    });

    test('reorderPages invokes method channel', () async {
      final result = await FlutterPdfToolkit.reorderPages(
        path: '/path/source.pdf',
        outputPath: '/path/reordered.pdf',
        pageOrder: [3, 1, 2],
      );

      expect(result, '/path/to/reordered.pdf');
      expect(log, hasLength(1));
      expect(log.first.method, 'reorderPdf');
      expect(log.first.arguments, <String, dynamic>{
        'path': '/path/source.pdf',
        'outputPath': '/path/reordered.pdf',
        'pageOrder': [3, 1, 2],
      });
    });

    test('downloadPdf invokes method channel', () async {
      final result = await FlutterPdfToolkit.downloadPdf(
        sourcePath: '/path/merged.pdf',
        fileName: 'output.pdf',
      );

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'downloadPdf');
      expect(log.first.arguments, <String, dynamic>{
        'sourcePath': '/path/merged.pdf',
        'fileName': 'output.pdf',
      });
    });
  });
}
