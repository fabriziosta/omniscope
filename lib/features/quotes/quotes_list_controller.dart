import 'package:flutter/foundation.dart';

import '../../core/app_copy.dart';
import '../../core/market_error_copy.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';

/// Screen-scoped quotes loader with page-sized fetches and race-safe gens.
///
/// Optional [symbolQuery] filters the in-memory catalog first, then pages
/// [MarketDataClient.getQuotes] over matches only.
class QuotesListController extends ChangeNotifier {
  QuotesListController({
    required this._client,
    required List<String> symbols,
    this.errorTitle = AppCopy.couldNotLoadQuotes,
    this.pageSize = defaultPageSize,
  }) : _symbols = List<String>.unmodifiable(symbols);

  static const defaultPageSize = 15;

  final MarketDataClient _client;
  List<String> _symbols;
  final String errorTitle;
  final int pageSize;

  var _loadGen = 0;
  var _loading = false;
  var _loadingMore = false;
  var _hasLoaded = false;
  var _fetchedCount = 0;
  String _symbolQuery = '';
  String? _error;
  String? _lastPagingError;
  DateTime? _fetchedAt;
  List<Quote> _quotes = const [];

  List<String> get symbols => _symbols;

  /// Normalized catalog filter (trimmed, lowercased). Empty = browse all.
  String get symbolQuery => _symbolQuery;

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  String? get lastPagingError => _lastPagingError;
  DateTime? get fetchedAt => _fetchedAt;
  List<Quote> get quotes => _quotes;
  bool get hasError => _error != null;
  bool get isEmpty => _hasLoaded && !hasError && _quotes.isEmpty;

  /// Symbols currently being paged (full catalog or query matches).
  List<String> get activeSymbols => _activeSymbols;

  bool get hasMore => _fetchedCount < _activeSymbols.length;

  /// Count of symbols in the active (possibly filtered) list.
  int get totalSymbols => _activeSymbols.length;
  int get fetchedCount => _fetchedCount;

  List<String> get _activeSymbols {
    if (_symbolQuery.isEmpty) return _symbols;
    return [
      for (final s in _symbols)
        if (s.toLowerCase().contains(_symbolQuery)) s,
    ];
  }

  /// Replace the browse list (e.g. after Crypto.com instrument discovery).
  /// Does not fetch — call [refresh] afterward. Keeps [symbolQuery].
  void updateSymbols(List<String> symbols) {
    _symbols = List<String>.unmodifiable(symbols);
    notifyListeners();
  }

  /// Filter the catalog by symbol substring, then fetch the first page of
  /// matches. No-op when the normalized query is unchanged.
  Future<void> setSymbolQuery(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized == _symbolQuery) return;
    _symbolQuery = normalized;
    await refresh();
  }

  /// Clears a soft paging error after the UI has shown it (e.g. toast).
  void clearPagingError() {
    if (_lastPagingError == null) return;
    _lastPagingError = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final gen = ++_loadGen;
    _loading = true;
    _loadingMore = false;
    _error = null;
    _lastPagingError = null;
    _fetchedCount = 0;
    _quotes = const [];
    _hasLoaded = false;
    notifyListeners();

    try {
      await _fetchNextPage(gen: gen, replace: true);
    } catch (e, st) {
      debugPrint('QuotesListController refresh failed: $e\n$st');
      if (gen != _loadGen) return;
      _hasLoaded = true;
      _loading = false;
      _loadingMore = false;
      _error = userFacingMarketError(e);
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore || hasError) return;
    final gen = _loadGen;
    _loadingMore = true;
    _lastPagingError = null;
    notifyListeners();
    try {
      await _fetchNextPage(gen: gen, replace: false);
    } catch (e, st) {
      debugPrint('QuotesListController loadMore failed: $e\n$st');
      if (gen != _loadGen) return;
      _loadingMore = false;
      _lastPagingError = AppCopy.couldNotLoadMoreQuotes;
      notifyListeners();
    }
  }

  Future<void> _fetchNextPage({
    required int gen,
    required bool replace,
  }) async {
    final active = _activeSymbols;
    if (active.isEmpty) {
      if (gen != _loadGen) return;
      _quotes = const [];
      _fetchedCount = 0;
      _hasLoaded = true;
      _loading = false;
      _loadingMore = false;
      _error = null;
      _lastPagingError = null;
      _fetchedAt = DateTime.now();
      notifyListeners();
      return;
    }

    final slice = active.skip(_fetchedCount).take(pageSize).toList();
    if (slice.isEmpty) {
      if (gen != _loadGen) return;
      _loading = false;
      _loadingMore = false;
      notifyListeners();
      return;
    }

    final list = await _client.getQuotes(slice);
    if (gen != _loadGen) return;

    // Preserve browse order; drop symbols that failed to quote.
    final bySymbol = {for (final q in list) q.symbol: q};
    final pageQuotes = [
      for (final s in slice)
        if (bySymbol.containsKey(s)) bySymbol[s]!,
    ];

    _quotes = replace ? pageQuotes : [..._quotes, ...pageQuotes];
    _fetchedCount += slice.length;
    _hasLoaded = true;
    _loading = false;
    _loadingMore = false;
    _error = null;
    _lastPagingError = null;
    _fetchedAt = DateTime.now();
    notifyListeners();
  }
}
