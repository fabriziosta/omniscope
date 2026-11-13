import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'equity_data_source.dart';
import 'market_data_client.dart';
import 'models.dart';

/// Keyless Yahoo Finance chart API client (unofficial, educational use).
///
/// Uses `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`.
/// Native targets send a browser-like User-Agent. On **Web**, Yahoo does not
/// send `Access-Control-Allow-Origin`, so browsers block direct fetches; chart
/// URLs are routed through [webCorsProxyPrefix] (default `proxy.cors.dev`).
/// Endpoints can change without notice.
class YahooMarketDataClient implements MarketDataClient {
  YahooMarketDataClient({
    http.Client? httpClient,
    this.webCorsProxyPrefix = defaultWebCorsProxyPrefix,
  }) : _http = httpClient ?? http.Client();

  static const EquityDataSource meta = EquityDataSource(
    id: 'yahoo',
    displayName: 'Yahoo Finance',
    description: 'Indices, ETFs, and stocks via the public chart API',
  );

  /// Public GET CORS proxy used only when [kIsWeb] is true.
  static const defaultWebCorsProxyPrefix = 'https://proxy.cors.dev/';

  static const _base = 'https://query1.finance.yahoo.com';
  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final http.Client _http;

  /// Prefix prepended to the Yahoo URL on Web only (must end with `/`).
  final String webCorsProxyPrefix;

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return const [];
    final quotes = <Quote>[];
    Object? lastError;
    for (final symbol in symbols) {
      try {
        final chart = await _fetchChart(symbol, range: '5d', interval: '1d');
        quotes.add(_quoteFromChart(chart));
      } catch (e) {
        lastError = e;
      }
    }
    if (quotes.isEmpty && lastError != null) {
      throw lastError;
    }
    return quotes;
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    final chart = await _fetchChart(symbol, range: range, interval: interval);
    return _candlesFromChart(chart);
  }

  Future<Map<String, dynamic>> _fetchChart(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    final encoded = Uri.encodeComponent(symbol);
    final yahooUri = Uri.parse(
      '$_base/v8/finance/chart/$encoded'
      '?range=$range&interval=$interval',
    );
    // Browsers enforce CORS; Yahoo chart responses omit ACAO. Native IO does not.
    final uri = kIsWeb
        ? Uri.parse('$webCorsProxyPrefix$yahooUri')
        : yahooUri;

    // Free CORS proxies reject / browsers forbid setting User-Agent from JS.
    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': _userAgent,
    };

    late final http.Response response;
    try {
      response = await _http.get(uri, headers: headers);
    } catch (e) {
      throw MarketDataException('Network error fetching $symbol: $e');
    }

    if (response.statusCode != 200) {
      final corsHint = response.headers['x-cors-error'];
      throw MarketDataException(
        corsHint != null
            ? 'Yahoo/CORS proxy error for $symbol: $corsHint'
            : 'Yahoo returned ${response.statusCode} for $symbol',
        statusCode: response.statusCode,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final chart = body['chart'] as Map<String, dynamic>?;
    final error = chart?['error'];
    if (error != null) {
      throw MarketDataException(
        'Yahoo error for $symbol: ${error['description'] ?? error}',
      );
    }

    final result = chart?['result'];
    if (result is! List || result.isEmpty) {
      throw MarketDataException('No chart data for $symbol');
    }
    return result.first as Map<String, dynamic>;
  }

  Quote _quoteFromChart(Map<String, dynamic> chart) {
    final meta = chart['meta'] as Map<String, dynamic>? ?? const {};
    final symbol = meta['symbol'] as String? ?? '';
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    final previous =
        (meta['chartPreviousClose'] as num?)?.toDouble() ??
        (meta['previousClose'] as num?)?.toDouble();

    double? change;
    double? changePercent;
    if (price != null && previous != null && previous != 0) {
      change = price - previous;
      changePercent = change / previous;
    }

    // Prefer last close from series if meta price is missing.
    final resolvedPrice = price ?? _lastClose(chart);
    if (resolvedPrice == null) {
      throw MarketDataException('Missing price for $symbol');
    }

    return Quote(
      symbol: symbol,
      name: meta['longName'] as String? ?? meta['shortName'] as String?,
      price: resolvedPrice,
      currency: meta['currency'] as String?,
      previousClose: previous,
      change: change,
      changePercent: changePercent,
      exchange: meta['fullExchangeName'] as String? ??
          meta['exchangeName'] as String?,
      dataSource: YahooMarketDataClient.meta.displayName,
      dataSourceId: YahooMarketDataClient.meta.id,
    );
  }

  List<Candle> _candlesFromChart(Map<String, dynamic> chart) {
    final timestamps = (chart['timestamp'] as List?)?.cast<int>() ?? const [];
    final indicators = chart['indicators'] as Map<String, dynamic>? ?? const {};
    final quotes = indicators['quote'] as List? ?? const [];
    if (quotes.isEmpty || timestamps.isEmpty) return const [];

    final q = quotes.first as Map<String, dynamic>;
    final closes = (q['close'] as List?) ?? const [];
    final opens = (q['open'] as List?) ?? const [];
    final highs = (q['high'] as List?) ?? const [];
    final lows = (q['low'] as List?) ?? const [];
    final volumes = (q['volume'] as List?) ?? const [];

    final candles = <Candle>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = i < closes.length ? (closes[i] as num?)?.toDouble() : null;
      if (close == null) continue;
      candles.add(
        Candle(
          time: DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000),
          close: close,
          open: i < opens.length ? (opens[i] as num?)?.toDouble() : null,
          high: i < highs.length ? (highs[i] as num?)?.toDouble() : null,
          low: i < lows.length ? (lows[i] as num?)?.toDouble() : null,
          volume: i < volumes.length ? (volumes[i] as num?)?.toDouble() : null,
        ),
      );
    }
    return candles;
  }

  double? _lastClose(Map<String, dynamic> chart) {
    final candles = _candlesFromChart(chart);
    if (candles.isEmpty) return null;
    return candles.last.close;
  }
}
