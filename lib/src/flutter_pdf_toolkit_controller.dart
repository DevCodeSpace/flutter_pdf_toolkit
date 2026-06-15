import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PdfBookmarkItem {
  const PdfBookmarkItem({required this.title, required this.pageNumber});

  final String title;
  final int pageNumber;
}

class FlutterPdfToolkitController extends ChangeNotifier {
  FlutterPdfToolkitController();

  MethodChannel? _channel;
  int _pageNumber = 1;
  int _pageCount = 0;
  double _zoomLevel = 1.0;
  String? _searchText;
  int _searchResultCount = 0;
  int _currentSearchResultIndex = 0;
  List<PdfBookmarkItem> _bookmarks = const [];
  bool _isReady = false;
  bool? _pendingDarkMode;

  Future<String?> Function(bool retry)? onPasswordRequired;
  String? _errorMessage;

  int get pageNumber => _pageNumber;
  int get pageCount => _pageCount;
  double get zoomLevel => _zoomLevel;
  String? get searchText => _searchText;
  int get searchResultCount => _searchResultCount;
  int get currentSearchResultIndex => _currentSearchResultIndex;
  List<PdfBookmarkItem> get bookmarks => _bookmarks;
  bool get isReady => _isReady;
  String? get errorMessage => _errorMessage;

  void attachChannel(MethodChannel channel) {
    _channel = channel;
    _isReady = false;
    _errorMessage = null;
    _channel!.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        _isReady = true;
        _errorMessage = null;
        if (_pendingDarkMode != null) {
          final bool enabled = _pendingDarkMode!;
          _pendingDarkMode = null;
          await _sendDarkMode(enabled);
        }
        break;
      case 'onPageChanged':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        _pageNumber = (args['pageNumber'] as num?)?.toInt() ?? _pageNumber;
        _pageCount = (args['pageCount'] as num?)?.toInt() ?? _pageCount;
        break;
      case 'onZoomChanged':
        _zoomLevel = (call.arguments as num?)?.toDouble() ?? _zoomLevel;
        break;
      case 'onSearchChanged':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        _searchText = args['text'] as String?;
        _searchResultCount = (args['count'] as num?)?.toInt() ?? 0;
        _currentSearchResultIndex = (args['index'] as num?)?.toInt() ?? 0;
        break;
      case 'onBookmarks':
        final List<dynamic> raw = call.arguments as List<dynamic>;
        _bookmarks = raw
            .map((dynamic e) {
              final Map<dynamic, dynamic> map = e as Map<dynamic, dynamic>;
              return PdfBookmarkItem(
                title: map['title'] as String? ?? '',
                pageNumber: (map['pageNumber'] as num?)?.toInt() ?? 1,
              );
            })
            .toList(growable: false);
        break;
      case 'onPasswordRequired':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        final bool retry = args['retry'] as bool? ?? false;
        if (onPasswordRequired != null) {
          return await onPasswordRequired!(retry);
        }
        return null;
      case 'onError':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        _errorMessage = args['message'] as String?;
        break;
    }
    notifyListeners();
  }

  Future<void> jumpToPage(int pageNumber) async {
    await _channel?.invokeMethod('jumpToPage', {'pageNumber': pageNumber});
  }

  Future<void> nextPage() =>
      _channel?.invokeMethod('nextPage') ?? Future.value();

  Future<void> previousPage() =>
      _channel?.invokeMethod('previousPage') ?? Future.value();

  Future<void> zoomIn([double step = 0.25]) async {
    await _channel?.invokeMethod('zoomIn', {'step': step});
  }

  Future<void> zoomOut([double step = 0.25]) async {
    await _channel?.invokeMethod('zoomOut', {'step': step});
  }

  Future<void> resetZoom() async {
    await _channel?.invokeMethod('resetZoom');
  }

  Future<void> search(String text, {bool caseSensitive = false}) async {
    await _channel?.invokeMethod('search', {
      'text': text,
      'caseSensitive': caseSensitive,
    });
  }

  Future<void> requestBookmarks() async {
    await _channel?.invokeMethod('requestBookmarks');
  }

  Future<void> clearSearch() async {
    await _channel?.invokeMethod('clearSearch');
  }

  Future<void> nextSearchResult() async {
    await _channel?.invokeMethod('nextSearchResult');
  }

  Future<void> previousSearchResult() async {
    await _channel?.invokeMethod('previousSearchResult');
  }

  Future<void> openBookmarks() async {
    await _channel?.invokeMethod('openBookmarks');
  }

  Future<Uint8List?> getPageThumbnail(int pageNumber, {int width = 200}) async {
    final dynamic result = await _channel?.invokeMethod('getPageThumbnail', {
      'pageNumber': pageNumber,
      'width': width,
    });
    if (result is Uint8List) {
      return result;
    }
    if (result is List<int>) {
      return Uint8List.fromList(result);
    }
    return null;
  }

  Future<void> setDarkMode(bool enabled) async {
    _pendingDarkMode = enabled;
    if (!_isReady) {
      return;
    }
    await _sendDarkMode(enabled);
  }

  Future<void> _sendDarkMode(bool enabled) async {
    final MethodChannel? channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod('setDarkMode', {'enabled': enabled});
      if (_pendingDarkMode == enabled) {
        _pendingDarkMode = null;
      }
    } on MissingPluginException {
      _pendingDarkMode = enabled;
    }
  }
}
