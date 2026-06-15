import 'dart:convert';

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
