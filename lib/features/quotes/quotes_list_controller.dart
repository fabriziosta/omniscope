import 'package:flutter/foundation.dart';

import '../../core/app_copy.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';

/// Screen-scoped quotes loader with page-sized fetches and race-safe gens.
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
  String? _error;
  List<Quote> _quotes = const [];

  List<String> get symbols => _symbols;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  List<Quote> get quotes => _quotes;
  bool get hasError => _error != null;
  bool get isEmpty => _hasLoaded && !hasError && _quotes.isEmpty;
  bool get hasMore => _fetchedCount < _symbols.length;
  int get totalSymbols => _symbols.length;
  int get fetchedCount => _fetchedCount;

  /// Replace the browse list (e.g. after Crypto.com instrument discovery).
  /// Does not fetch — call [refresh] afterward.
  void updateSymbols(List<String> symbols) {
    _symbols = List<String>.unmodifiable(symbols);
    notifyListeners();
  }

  Future<void> refresh() async {
    final gen = ++_loadGen;
    _loading = true;
    _loadingMore = false;
    _error = null;
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
      _error = AppCopy.checkConnection;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore || hasError) return;
    final gen = _loadGen;
    _loadingMore = true;
    notifyListeners();
    try {
      await _fetchNextPage(gen: gen, replace: false);
    } catch (e, st) {
      debugPrint('QuotesListController loadMore failed: $e\n$st');
      if (gen != _loadGen) return;
      _loadingMore = false;
      // Keep existing quotes; surface a soft error via debug only.
      notifyListeners();
    }
  }

  Future<void> _fetchNextPage({
    required int gen,
    required bool replace,
  }) async {
    if (_symbols.isEmpty) {
      if (gen != _loadGen) return;
      _quotes = const [];
      _fetchedCount = 0;
      _hasLoaded = true;
      _loading = false;
      _loadingMore = false;
      _error = null;
      notifyListeners();
      return;
    }

    final slice = _symbols.skip(_fetchedCount).take(pageSize).toList();
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
    notifyListeners();
  }
}
