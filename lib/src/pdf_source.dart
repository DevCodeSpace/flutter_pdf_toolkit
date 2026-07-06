import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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

  static final HttpClient _client = HttpClient();
  static final Map<String, Future<String>> _downloadCache =
      <String, Future<String>>{};
  static Future<String> Function(Uri uri, Map<String, String>? headers)?
  debugDownloadOverride;

  @override
  Future<String> resolveToFile() async {
    final Uri resolvedUri = normalizeNetworkPdfUrl(Uri.parse(url));
    final String cacheKey = _cacheKey(resolvedUri, headers);
    final Future<String> cached = _downloadCache.putIfAbsent(
      cacheKey,
      () => (debugDownloadOverride ?? _downloadToFile)(resolvedUri, headers),
    );
    return cached.catchError((Object error, StackTrace stackTrace) {
      _downloadCache.remove(cacheKey);
      debugPrint('Network PDF download failed: $error');
      return Future<String>.error(error, stackTrace);
    });
  }
}

Future<String> _downloadToFile(
  Uri resolvedUri,
  Map<String, String>? headers,
) async {
  final Uint8List bytes = await _downloadBytes(resolvedUri, headers);

  final Directory directory = await Directory.systemTemp.createTemp(
    'flutter_pdf_toolkit',
  );
  final File file = File('${directory.path}/document.pdf');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> _downloadBytes(
  Uri resolvedUri,
  Map<String, String>? headers, {
  int redirectAttempts = 0,
}) async {
  debugPrint('Downloading from: $resolvedUri');
  final HttpClientRequest request = await NetworkPdfSource._client.getUrl(
    resolvedUri,
  );
  request.followRedirects = true;
  request.maxRedirects = 5;
  request.headers.set(
    HttpHeaders.acceptHeader,
    'application/pdf,application/octet-stream,*/*',
  );
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  );
  headers?.forEach(request.headers.add);

  final HttpClientResponse response = await request.close();
  debugPrint('Response status: ${response.statusCode}');

  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'Failed to download PDF: ${response.statusCode}',
      uri: resolvedUri,
    );
  }

  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in response) {
    builder.add(chunk);
  }
  final Uint8List bytes = builder.takeBytes();
  debugPrint('Downloaded ${bytes.length} bytes');

  if (_looksLikePdf(bytes, response.headers.contentType)) {
    return bytes;
  }

  if (_isGoogleDriveUri(resolvedUri) && redirectAttempts < 1) {
    final Uri? confirmationUri = _googleDriveConfirmationUri(
      resolvedUri,
      bytes,
    );
    if (confirmationUri != null) {
      debugPrint(
        'Google Drive confirmation detected, retrying with: $confirmationUri',
      );
      return _downloadBytes(
        confirmationUri,
        headers,
        redirectAttempts: redirectAttempts + 1,
      );
    }
  }

  throw const FormatException(
    'The downloaded file was not a PDF. If this is a Google Drive link, make sure sharing is enabled for direct download.',
  );
}

String _cacheKey(Uri uri, Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) {
    return uri.toString();
  }
  final List<String> sortedKeys = headers.keys.toList()..sort();
  final StringBuffer buffer = StringBuffer(uri.toString());
  for (final String key in sortedKeys) {
    buffer.write('|');
    buffer.write(key);
    buffer.write('=');
    buffer.write(headers[key]);
  }
  return buffer.toString();
}

Uri normalizeNetworkPdfUrl(Uri uri) {
  final String host = uri.host.toLowerCase();

  if (host == 'drive.google.com' || host == 'www.drive.google.com') {
    final List<String> segments = uri.pathSegments;

    if (segments.length >= 3 && segments[0] == 'file' && segments[1] == 'd') {
      final String fileId = segments[2];
      return Uri.https('drive.google.com', '/uc', {
        'export': 'download',
        'id': fileId,
      });
    }

    if (uri.path == '/open') {
      final String? fileId = uri.queryParameters['id'];
      if (fileId != null && fileId.isNotEmpty) {
        return Uri.https('drive.google.com', '/uc', {
          'export': 'download',
          'id': fileId,
        });
      }
    }

    if (uri.path == '/uc') {
      final String? fileId = uri.queryParameters['id'];
      if (fileId != null && fileId.isNotEmpty) {
        final Map<String, String> queryParams = Map.from(uri.queryParameters);
        queryParams['export'] = 'download';
        return uri.replace(queryParameters: queryParams);
      }
    }
  }

  if (host == 'docs.google.com' || host == 'www.docs.google.com') {
    final String? nestedUrl = uri.queryParameters['url'];
    if (nestedUrl != null && nestedUrl.isNotEmpty) {
      return Uri.parse(nestedUrl);
    }
  }

  return uri;
}

bool _isGoogleDriveUri(Uri uri) {
  final String host = uri.host.toLowerCase();
  return host == 'drive.google.com' || host == 'www.drive.google.com';
}

bool _looksLikePdf(Uint8List bytes, ContentType? contentType) {
  if (contentType != null) {
    final String mimeType = contentType.mimeType.toLowerCase();
    if (mimeType == 'application/pdf') {
      return true;
    }
  }

  if (bytes.length < 4) {
    return false;
  }

  return bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

Uri? _googleDriveConfirmationUri(Uri originalUri, Uint8List bytes) {
  final String body = utf8.decode(bytes, allowMalformed: true);
  final RegExp confirmPattern = RegExp(r'confirm=([0-9A-Za-z_-]+)');
  final Match? match = confirmPattern.firstMatch(body);
  if (match == null) {
    return null;
  }

  final String confirm = match.group(1)!;
  final Map<String, String> queryParameters = Map<String, String>.from(
    originalUri.queryParameters,
  );
  queryParameters['confirm'] = confirm;
  return originalUri.replace(queryParameters: queryParameters);
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
