import 'dart:async';

import 'caching_market_data_client.dart';
import 'market_data_client.dart';
import 'models.dart';

/// Market-data client that skips the shared UI TTL cache.
///
/// Used by agent tools and Run snapshot injection so specialists see fresher
/// quotes/history without changing Markets/Portfolio cache behavior. Still
/// coalesces identical in-flight requests to avoid stampedes.
class FreshMarketDataClient implements MarketDataClient {
  FreshMarketDataClient(MarketDataClient source)
      : _inner = source is CachingMarketDataClient ? source.inner : source;

  final MarketDataClient _inner;

  final Map<String, Future<List<Quote>>> _inflightQuoteBatches = {};
  final Map<String, Future<List<Candle>>> _inflightHistory = {};

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) {
    if (symbols.isEmpty) return Future.value(const []);
    final key = symbols.map(_quoteKey).toList()..sort();
    final batchKey = key.join(',');
    final existing = _inflightQuoteBatches[batchKey];
    if (existing != null) return existing;

    final future = () async {
      try {
        return await _inner.getQuotes(symbols);
      } finally {
        _inflightQuoteBatches.remove(batchKey);
      }
    }();
    _inflightQuoteBatches[batchKey] = future;
    return future;
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) {
    final key = '${_quoteKey(symbol)}|$range|$interval';
    final existing = _inflightHistory[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        return await _inner.getHistory(
          symbol,
          range: range,
          interval: interval,
        );
      } finally {
        _inflightHistory.remove(key);
      }
    }();
    _inflightHistory[key] = future;
    return future;
  }

  static String _quoteKey(String symbol) => symbol.trim().toUpperCase();
}
