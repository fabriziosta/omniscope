import 'dart:async';

import 'caching_market_data_client.dart';
import 'market_data_client.dart';
import 'models.dart';

/// Market-data client that skips the shared UI TTL cache.
///
/// Used by agent tools and Run snapshot injection so specialists see fresher
/// quotes/history without changing Markets/Portfolio cache behavior. Still
/// coalesces identical in-flight requests to avoid stampedes.
///
/// When [quoteTtl] / [historyTtl] are set, adds a short agent-turn cache over
/// the unwrapped provider (bypasses outer UI cache, reuses fetches within TTL).
class FreshMarketDataClient implements MarketDataClient {
  FreshMarketDataClient(
    MarketDataClient source, {
    this.quoteTtl,
    this.historyTtl,
  }) : _inner = _resolveInner(source, quoteTtl, historyTtl);

  final MarketDataClient _inner;

  final Duration? quoteTtl;
  final Duration? historyTtl;

  final Map<String, Future<List<Quote>>> _inflightQuoteBatches = {};
  final Map<String, Future<List<Candle>>> _inflightHistory = {};

  /// Short TTL layer for one agent user turn (snapshot + tools share fetches).
  factory FreshMarketDataClient.forAgentTurn(MarketDataClient source) {
    return FreshMarketDataClient(
      source,
      quoteTtl: const Duration(seconds: 8),
      historyTtl: const Duration(seconds: 8),
    );
  }

  static MarketDataClient _resolveInner(
    MarketDataClient source,
    Duration? quoteTtl,
    Duration? historyTtl,
  ) {
    final bypass = source is CachingMarketDataClient ? source.inner : source;
    if (quoteTtl == null && historyTtl == null) {
      return bypass;
    }
    return CachingMarketDataClient(
      bypass,
      quoteTtl: quoteTtl ?? const Duration(seconds: 8),
      historyTtl: historyTtl ?? const Duration(seconds: 8),
    );
  }

  bool get _usesShortTtl => quoteTtl != null || historyTtl != null;

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) {
    if (symbols.isEmpty) return Future.value(const []);
    if (_usesShortTtl) {
      return _inner.getQuotes(symbols);
    }
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
    if (_usesShortTtl) {
      return _inner.getHistory(
        symbol,
        range: range,
        interval: interval,
      );
    }
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
