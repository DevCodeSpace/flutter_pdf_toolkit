import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

sealed class PdfSource {
  const PdfSource();

  const factory PdfSource.asset(String assetPath, {AssetBundle? bundle}) =
      AssetPdfSource;

  const factory PdfSource.network(String url, {Map<String, String>? headers}) =
      NetworkPdfSource;

  const factory PdfSource.filePath(String path) = FilePathPdfSource;

  const factory PdfSource.bytes(Uint8List bytes) = MemoryPdfSource;

  factory PdfSource.base64(String base64String, {String? password}) =
      Base64PdfSource;

  Future<String> resolveToFile();
}

final class AssetPdfSource extends PdfSource {
  const AssetPdfSource(this.assetPath, {this.bundle});

  final String assetPath;
  final AssetBundle? bundle;

  @override
  Future<String> resolveToFile() async {
    final ByteData data = await (bundle ?? rootBundle).load(assetPath);
    return _writeTempPdf(data.buffer.asUint8List());
  }
}

final class NetworkPdfSource extends PdfSource {
  const NetworkPdfSource(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  Future<String> resolveToFile() async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    headers?.forEach(request.headers.add);
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to download PDF: ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }
    client.close(force: true);
    return _writeTempPdf(builder.takeBytes());
  }
}

final class FilePathPdfSource extends PdfSource {
  const FilePathPdfSource(this.path);

  final String path;

  @override
  Future<String> resolveToFile() async => path;
}

final class MemoryPdfSource extends PdfSource {
  const MemoryPdfSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<String> resolveToFile() async => _writeTempPdf(bytes);
}

final class Base64PdfSource extends PdfSource {
  Base64PdfSource(this.base64String, {this.password})
    : _bytes = Uint8List.fromList(_decodeBase64(base64String));

  final String base64String;
  final String? password;
  final Uint8List _bytes;

  Uint8List get bytes => _bytes;

  @override
  Future<String> resolveToFile() async => _writeTempPdf(bytes);
}

Future<String> _writeTempPdf(Uint8List bytes) async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'flutter_pdf_toolkit',
  );
  final File file = File('${directory.path}/document.pdf');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

List<int> _decodeBase64(String value) {
  final String normalized = value
      .trim()
      .replaceFirst(
        RegExp(r'^data:application\/pdf;base64,', caseSensitive: false),
        '',
      )
      .replaceAll('\n', '')
      .replaceAll('\r', '');
  return base64Decode(normalized);
}
