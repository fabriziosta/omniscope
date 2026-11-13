import 'dart:async';

import 'market_data_client.dart';
import 'models.dart';

/// In-memory TTL cache + in-flight coalescing over a [MarketDataClient].
///
/// Quotes and history stay process-local (no disk). Identical concurrent
/// requests share one underlying Future so remounts / agent Runs do not
/// stampede the network.
class CachingMarketDataClient implements MarketDataClient {
  CachingMarketDataClient(
    this._inner, {
    this.quoteTtl = const Duration(seconds: 30),
    this.historyTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MarketDataClient _inner;
  final Duration quoteTtl;
  final Duration historyTtl;
  final DateTime Function() _clock;

  final Map<String, _Timed<Quote>> _quotes = {};
  final Map<String, _Timed<List<Candle>>> _history = {};
  final Map<String, Future<List<Quote>>> _inflightQuoteBatches = {};
  final Map<String, Future<List<Candle>>> _inflightHistory = {};

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return const [];

    final now = _clock();
    final resultBySymbol = <String, Quote>{};
    final missing = <String>[];

    for (final symbol in symbols) {
      final key = _quoteKey(symbol);
      final cached = _quotes[key];
      if (cached != null && !cached.isExpired(now, quoteTtl)) {
        resultBySymbol[symbol] = cached.value;
      } else if (!missing.contains(symbol)) {
        missing.add(symbol);
      }
    }

    if (missing.isNotEmpty) {
      final fetched = await _fetchQuoteBatchCoalesced(missing);
      for (final quote in fetched) {
        resultBySymbol[quote.symbol] = quote;
        // Also index by requested casing when providers normalize symbols.
        for (final requested in missing) {
          if (_quoteKey(requested) == _quoteKey(quote.symbol)) {
            resultBySymbol[requested] = quote;
          }
        }
      }
    }

    return [
      for (final s in symbols)
        if (resultBySymbol.containsKey(s)) resultBySymbol[s]!,
    ];
  }

  Future<List<Quote>> _fetchQuoteBatchCoalesced(List<String> symbols) {
    final key = symbols.map(_quoteKey).toList()..sort();
    final batchKey = key.join(',');
    final existing = _inflightQuoteBatches[batchKey];
    if (existing != null) return existing;

    final future = () async {
      try {
        final list = await _inner.getQuotes(symbols);
        final at = _clock();
        for (final quote in list) {
          _quotes[_quoteKey(quote.symbol)] = _Timed(quote, at);
        }
        return list;
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
    final key = _historyKey(symbol, range: range, interval: interval);
    final now = _clock();
    final cached = _history[key];
    if (cached != null && !cached.isExpired(now, historyTtl)) {
      return Future.value(List<Candle>.from(cached.value));
    }

    final existing = _inflightHistory[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        final candles = await _inner.getHistory(
          symbol,
          range: range,
          interval: interval,
        );
        _history[key] = _Timed(List<Candle>.from(candles), _clock());
        return List<Candle>.from(candles);
      } finally {
        _inflightHistory.remove(key);
      }
    }();

    _inflightHistory[key] = future;
    return future;
  }

  /// Drops all cached entries (tests / forced refresh).
  void clear() {
    _quotes.clear();
    _history.clear();
  }

  static String _quoteKey(String symbol) => symbol.trim().toUpperCase();

  static String _historyKey(
    String symbol, {
    required String range,
    required String interval,
  }) =>
      '${_quoteKey(symbol)}|$range|$interval';
}

class _Timed<T> {
  _Timed(this.value, this.at);

  final T value;
  final DateTime at;

  bool isExpired(DateTime now, Duration ttl) => now.difference(at) >= ttl;
}
