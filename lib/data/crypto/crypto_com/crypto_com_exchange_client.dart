import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../core/async_pool.dart';
import '../../market/exchange_credentials.dart';
import '../../market/market_data_client.dart';
import '../../market/models.dart';
import '../../trading/order_models.dart';
import '../crypto_exchange.dart';
import '../crypto_exchange_client.dart';
import '../exchange_portfolio.dart';

/// Crypto.com Exchange REST adapter.
///
/// Public market data (tickers / candlesticks) needs no key. Optional
/// [credentials] from `.env` (`OMNISCOPE_CRYPTO_COM_API_KEY` / `_SECRET` /
/// `_TOKEN`) enable authenticated portfolio via `private/user-balance` and
/// live orders via `private/create-order`.
///
/// Base: `https://api.crypto.com/exchange/v1/`
/// - `GET /public/get-tickers`
/// - `GET /public/get-candlestick`
/// - `POST /private/user-balance` (HMAC-SHA256 signed)
/// - `POST /private/create-order` / `cancel-order` / `get-order-detail`
class CryptoComExchangeClient implements CryptoExchangeClient {
  CryptoComExchangeClient({
    http.Client? httpClient,
    this._credentials = ExchangeCredentials.empty,
  }) : _http = httpClient ?? http.Client();

  static const _base = 'https://api.crypto.com/exchange/v1';

  static const CryptoExchange meta = CryptoExchange(
    id: 'crypto_com',
    displayName: 'Crypto.com',
    // Curated fallback / landing preview. Full USD spot catalog comes from
    // [browseSymbols] via `public/get-instruments` when available.
    defaultSymbols: [
      'BTC_USD',
      'ETH_USD',
      'SOL_USD',
      'XRP_USD',
      'ADA_USD',
      'DOGE_USD',
      'AVAX_USD',
      'DOT_USD',
      'LINK_USD',
      'MATIC_USD',
      'LTC_USD',
      'BCH_USD',
      'ATOM_USD',
      'UNI_USD',
      'NEAR_USD',
      'APT_USD',
      'ARB_USD',
      'OP_USD',
      'SUI_USD',
      'SHIB_USD',
      'PEPE_USD',
      'TRX_USD',
      'XLM_USD',
      'ALGO_USD',
      'FIL_USD',
      'ICP_USD',
      'AAVE_USD',
      'MKR_USD',
      'CRV_USD',
      'SAND_USD',
    ],
  );

  /// Spot instrument names like `BTC_USD` / `ETH_USDT`.
  static final _spotSymbol = RegExp(r'^[A-Z0-9]+_[A-Z0-9]+$');

  /// Parallel per-symbol ticker fetches when bulk tickers are unavailable.
  static const quoteFetchConcurrency = 5;

  /// How long [listSpotUsdSymbols] / [browseSymbols] reuse one instruments list.
  static const instrumentsCacheTtl = Duration(hours: 1);

  final http.Client _http;

  ExchangeCredentials _credentials;

  List<String>? _cachedSpotUsdSymbols;
  DateTime? _cachedSpotUsdSymbolsAt;

  /// Local credentials (`.env` / Settings UI; may be empty for public endpoints).
  ExchangeCredentials get credentials => _credentials;

  /// Refresh credentials without recreating the client (Settings dual-sync).
  void setCredentials(ExchangeCredentials value) {
    _credentials = value;
  }

  /// Whether an API key or token was pre-configured for this exchange.
  bool get hasCredentials => credentials.isConfigured;

  @override
  CryptoExchange get exchange => meta;

  @override
  bool get supportsLivePortfolio => true;

  @override
  bool get canFetchPortfolio =>
      credentials.hasApiKey && credentials.hasApiSecret;

  @override
  bool get supportsLiveTrading => true;

  @override
  bool get canPlaceOrders =>
      credentials.hasApiKey && credentials.hasApiSecret;

  @override
  bool handlesSymbol(String symbol) {
    if (meta.defaultSymbols.contains(symbol)) return true;
    return _spotSymbol.hasMatch(symbol);
  }

  @override
  Future<List<String>> browseSymbols() async {
    try {
      final discovered = await listSpotUsdSymbols();
      if (discovered.isEmpty) return meta.defaultSymbols;
      // Featured defaults first, then the rest of the public USD spot catalog.
      final seen = <String>{};
      final ordered = <String>[];
      for (final s in [...meta.defaultSymbols, ...discovered]) {
        if (seen.add(s)) ordered.add(s);
      }
      return ordered;
    } catch (e, st) {
      developer.log(
        'Crypto.com browseSymbols failed, using defaults: $e',
        name: 'CryptoComExchangeClient',
        stackTrace: st,
      );
      return meta.defaultSymbols;
    }
  }

  /// Public USD spot pairs from `GET /public/get-instruments`.
  Future<List<String>> listSpotUsdSymbols() async {
    final now = DateTime.now();
    final cached = _cachedSpotUsdSymbols;
    final at = _cachedSpotUsdSymbolsAt;
    if (cached != null &&
        at != null &&
        now.difference(at) < instrumentsCacheTtl) {
      return List<String>.from(cached);
    }

    final body = await _getJson('/public/get-instruments', const {});
    final data = _resultData(body);
    final symbols = <String>[];
    for (final row in data) {
      final symbol = (row['symbol'] as String?)?.trim() ??
          (row['instrument_name'] as String?)?.trim();
      if (symbol == null || symbol.isEmpty) continue;
      if (!_spotSymbol.hasMatch(symbol)) continue;

      final instType = (row['inst_type'] as String?)?.toUpperCase() ??
          (row['instrument_type'] as String?)?.toUpperCase() ??
          '';
      // Prefer explicit spot; accept missing type when symbol looks like BASE_QUOTE.
      if (instType.isNotEmpty &&
          instType != 'CCY_PAIR' &&
          instType != 'SPOT') {
        continue;
      }

      final quote = (row['quote_ccy'] as String?)?.toUpperCase() ??
          (row['quote_currency'] as String?)?.toUpperCase() ??
          '';
      final endsUsd = symbol.endsWith('_USD');
      if (quote != 'USD' && !endsUsd) continue;

      final tradable = row['tradable'];
      if (tradable is bool && !tradable) continue;

      symbols.add(symbol);
    }
    symbols.sort();
    _cachedSpotUsdSymbols = symbols;
    _cachedSpotUsdSymbolsAt = now;
    return List<String>.from(symbols);
  }

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return const [];

    try {
      final bulk = await _quotesFromBulkTickers(symbols);
      if (bulk.isNotEmpty) return bulk;
    } catch (e, st) {
      developer.log(
        'Crypto.com bulk get-tickers failed, falling back: $e',
        name: 'CryptoComExchangeClient',
        stackTrace: st,
      );
    }

    return mapPool<String, Quote>(
      items: symbols,
      concurrency: quoteFetchConcurrency,
      mapper: (symbol) async {
        final body = await _getJson(
          '/public/get-tickers',
          {'instrument_name': symbol},
        );
        final data = _resultData(body);
        if (data.isEmpty) {
          throw MarketDataException('No ticker data for $symbol');
        }
        return quoteFromTicker(data.first, fallbackSymbol: symbol);
      },
      onError: (_, _) => null,
    );
  }

  /// One `get-tickers` call (no instrument filter), then keep requested symbols.
  Future<List<Quote>> _quotesFromBulkTickers(List<String> symbols) async {
    final wanted = {for (final s in symbols) s.toUpperCase(): s};
    final body = await _getJson('/public/get-tickers', const {});
    final data = _resultData(body);
    final bySymbol = <String, Quote>{};
    for (final row in data) {
      final raw = (row['i'] as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      final key = raw.toUpperCase();
      if (!wanted.containsKey(key)) continue;
      try {
        bySymbol[key] = quoteFromTicker(row, fallbackSymbol: wanted[key]);
      } catch (_) {
        // Skip malformed rows; per-symbol fallback may recover.
      }
    }
    return [
      for (final s in symbols)
        if (bySymbol.containsKey(s.toUpperCase()))
          bySymbol[s.toUpperCase()]!,
    ];
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    final mapped = _mapRange(range: range, interval: interval);
    final body = await _getJson(
      '/public/get-candlestick',
      {
        'instrument_name': symbol,
        'timeframe': mapped.timeframe,
        'count': '${mapped.count}',
      },
    );
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    final raw = result['data'] as List? ?? const [];
    return [
      for (final row in raw)
        if (row is Map<String, dynamic>) candleFromRow(row),
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    if (!canFetchPortfolio) {
      throw MarketDataException(
        'Crypto.com API key and secret are required for live portfolio',
      );
    }

    final body = await _postPrivate(
      'private/user-balance',
      const <String, dynamic>{},
    );
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    final data = result['data'] as List? ?? const [];
    if (data.isEmpty || data.first is! Map<String, dynamic>) {
      throw MarketDataException('Crypto.com returned empty user balance');
    }
    return portfolioFromUserBalance(
      data.first as Map<String, dynamic>,
      exchangeId: meta.id,
      exchangeName: meta.displayName,
    );
  }

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail(
        'Crypto.com API key and secret are required to place orders',
      );
    }
    if (request.exchangeId.isNotEmpty && request.exchangeId != meta.id) {
      return OrderResult.fail(
        'Order exchange ${request.exchangeId} does not match Crypto.com',
      );
    }
    final symbol = request.symbol.trim().toUpperCase();
    if (symbol.isEmpty || !handlesSymbol(symbol)) {
      return OrderResult.fail('Unsupported Crypto.com symbol: $symbol');
    }
    if (request.quantity <= 0) {
      return const OrderResult.fail('Quantity must be greater than zero.');
    }

    final params = <String, dynamic>{
      'instrument_name': symbol,
      'side': request.side.apiValue,
      'type': request.type == OrderType.limit ? 'LIMIT' : 'MARKET',
      'quantity': _qtyString(request.quantity),
    };
    if (request.type == OrderType.limit) {
      final price = request.limitPrice;
      if (price == null || price <= 0) {
        return const OrderResult.fail('Limit price is required for limit orders');
      }
      params['price'] = _qtyString(price);
    }
    final clientId = request.clientOrderId?.trim();
    if (clientId != null && clientId.isNotEmpty) {
      params['client_oid'] = clientId;
    }

    try {
      final body = await _postPrivate('private/create-order', params);
      return orderResultFromCreate(body);
    } on MarketDataException catch (e) {
      return OrderResult.fail(e.message);
    } catch (e) {
      return OrderResult.fail('$e');
    }
  }

  @override
  Future<OrderResult> cancelOrder(String orderId) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail(
        'Crypto.com API key and secret are required to cancel orders',
      );
    }
    final id = orderId.trim();
    if (id.isEmpty) {
      return const OrderResult.fail('Order id is required.');
    }
    try {
      final body = await _postPrivate(
        'private/cancel-order',
        {'order_id': id},
      );
      return orderResultFromCreate(body, fallbackOrderId: id);
    } on MarketDataException catch (e) {
      return OrderResult.fail(e.message);
    } catch (e) {
      return OrderResult.fail('$e');
    }
  }

  @override
  Future<OrderResult> getOrder(String orderId) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail(
        'Crypto.com API key and secret are required for order status',
      );
    }
    final id = orderId.trim();
    if (id.isEmpty) {
      return const OrderResult.fail('Order id is required.');
    }
    try {
      final body = await _postPrivate(
        'private/get-order-detail',
        {'order_id': id},
      );
      return orderResultFromDetail(body, fallbackOrderId: id);
    } on MarketDataException catch (e) {
      return OrderResult.fail(e.message);
    } catch (e) {
      return OrderResult.fail('$e');
    }
  }

  /// Visible for unit tests — map create-order envelope → [OrderResult].
  static OrderResult orderResultFromCreate(
    Map<String, dynamic> body, {
    String? fallbackOrderId,
  }) {
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    final orderId = (result['order_id'] as String?) ??
        (result['orderId'] as String?) ??
        fallbackOrderId;
    if (orderId == null || orderId.isEmpty) {
      return const OrderResult.fail('Crypto.com create-order returned no order id');
    }
    final status = result['status'] as String? ??
        result['order_status'] as String?;
    return OrderResult.ok(
      orderId: orderId,
      rawStatus: status,
      message: body['message'] as String?,
    );
  }

  /// Visible for unit tests — map get-order-detail envelope → [OrderResult].
  static OrderResult orderResultFromDetail(
    Map<String, dynamic> body, {
    String? fallbackOrderId,
  }) {
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    final orderInfo = result['order_info'] as Map<String, dynamic>? ?? result;
    final orderId = (orderInfo['order_id'] as String?) ??
        (orderInfo['orderId'] as String?) ??
        fallbackOrderId;
    if (orderId == null || orderId.isEmpty) {
      return const OrderResult.fail('Crypto.com order detail returned no order id');
    }
    final status = orderInfo['status'] as String? ??
        orderInfo['order_status'] as String?;
    return OrderResult.ok(
      orderId: orderId,
      rawStatus: status,
      message: body['message'] as String?,
    );
  }

  static String _qtyString(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    var s = value.toStringAsFixed(8);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    late final http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
    } catch (e) {
      throw MarketDataException('Network error calling Crypto.com: $e');
    }

    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> _postPrivate(
    String method,
    Map<String, dynamic> params, {
    int? id,
    int? nonce,
  }) async {
    final apiKey = credentials.apiKey!;
    final apiSecret = credentials.apiSecret!;
    final requestId = id ?? DateTime.now().millisecondsSinceEpoch;
    final requestNonce = nonce ?? DateTime.now().millisecondsSinceEpoch;
    final sig = signRequest(
      method: method,
      id: requestId,
      apiKey: apiKey,
      params: params,
      nonce: requestNonce,
      apiSecret: apiSecret,
    );

    final payload = <String, dynamic>{
      'id': requestId,
      'method': method,
      'api_key': apiKey,
      'params': params,
      'nonce': requestNonce,
      'sig': sig,
    };

    late final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_base/$method'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      throw MarketDataException('Network error calling Crypto.com: $e');
    }

    return _decodeEnvelope(response);
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    if (response.statusCode != 200) {
      throw MarketDataException(
        'Crypto.com returned ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw MarketDataException('Crypto.com returned unexpected JSON');
    }
    final code = decoded['code'];
    if (code != null && code != 0) {
      throw MarketDataException(
        'Crypto.com error $code: ${decoded['message'] ?? 'unknown'}',
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _resultData(Map<String, dynamic> body) {
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    final data = result['data'] as List? ?? const [];
    return [
      for (final row in data)
        if (row is Map<String, dynamic>) row,
    ];
  }

  /// HMAC-SHA256 signature for private REST (visible for unit tests).
  static String signRequest({
    required String method,
    required int id,
    required String apiKey,
    required Map<String, dynamic> params,
    required int nonce,
    required String apiSecret,
  }) {
    final paramsString = paramsToString(params);
    final payload = '$method$id$apiKey$paramsString$nonce';
    final digest = Hmac(sha256, utf8.encode(apiSecret)).convert(
      utf8.encode(payload),
    );
    return digest.toString();
  }

  /// Crypto.com parameter string (sorted keys, no delimiters).
  static String paramsToString(Object? value) {
    if (value == null) return '';
    if (value is List) {
      return value.map(paramsToString).join();
    }
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      final buffer = StringBuffer();
      for (final key in keys) {
        buffer.write(key);
        buffer.write(paramsToString(value[key]));
      }
      return buffer.toString();
    }
    return '$value';
  }

  /// Visible for unit tests — map `private/user-balance` row → snapshot.
  static ExchangePortfolioSnapshot portfolioFromUserBalance(
    Map<String, dynamic> row, {
    required String exchangeId,
    required String exchangeName,
  }) {
    final currency = (row['instrument_name'] as String?) ?? 'USD';
    final positions = row['position_balances'] as List? ?? const [];
    final balances = <ExchangeBalance>[
      for (final raw in positions)
        if (raw is Map<String, dynamic>)
          ExchangeBalance(
            asset: (raw['instrument_name'] as String?) ?? '',
            quantity: _asDouble(raw['quantity']) ?? 0,
            marketValue: _asDouble(raw['market_value']),
            available: _asDouble(raw['max_withdrawal_balance']),
            reserved: _asDouble(raw['reserved_qty']),
          ),
    ]
        .where((b) => b.asset.isNotEmpty && b.quantity.abs() > 1e-12)
        .toList()
      ..sort((a, b) => (b.marketValue ?? 0).compareTo(a.marketValue ?? 0));

    return ExchangePortfolioSnapshot(
      exchangeId: exchangeId,
      exchangeName: exchangeName,
      totalValue: _asDouble(row['total_cash_balance']),
      availableValue: _asDouble(row['total_available_balance']),
      currency: currency,
      balances: balances,
    );
  }

  /// Visible for unit tests — map one ticker row → [Quote].
  static Quote quoteFromTicker(
    Map<String, dynamic> row, {
    String? fallbackSymbol,
  }) {
    final symbol = (row['i'] as String?) ?? fallbackSymbol ?? '';
    final price = _asDouble(row['a']);
    if (price == null) {
      throw MarketDataException('Missing last price for $symbol');
    }
    // Docs sample: `c` is a 24h fractional change (e.g. 0.039…).
    final changePercent = _asDouble(row['c']);
    final change = changePercent == null
        ? null
        : price - (price / (1 + changePercent));

    final parts = symbol.split('_');
    final base = parts.isNotEmpty ? parts.first : symbol;
    final quoteCcy = parts.length > 1 ? parts.last : 'USD';

    return Quote(
      symbol: symbol,
      name: '$base / $quoteCcy',
      price: price,
      currency: quoteCcy,
      change: change,
      changePercent: changePercent,
      exchange: meta.displayName,
      dataSource: meta.displayName,
      dataSourceId: meta.id,
    );
  }

  /// Visible for unit tests — map one candlestick row → [Candle].
  static Candle candleFromRow(Map<String, dynamic> row) {
    final close = _asDouble(row['c']);
    if (close == null) {
      throw MarketDataException('Missing candle close');
    }
    final ts = row['t'];
    final ms = ts is int
        ? ts
        : ts is num
            ? ts.toInt()
            : int.tryParse('$ts') ?? 0;
    return Candle(
      time: DateTime.fromMillisecondsSinceEpoch(ms),
      close: close,
      open: _asDouble(row['o']),
      high: _asDouble(row['h']),
      low: _asDouble(row['l']),
      volume: _asDouble(row['v']),
    );
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static ({String timeframe, int count}) _mapRange({
    required String range,
    required String interval,
  }) {
    // App uses Yahoo-style range/interval; map to CDC daily candles by default.
    if (interval == '1d' || interval == '1D') {
      return switch (range) {
        '1mo' || '1m' => (timeframe: '1D', count: 32),
        '3mo' || '3m' => (timeframe: '1D', count: 96),
        '1y' || '12mo' => (timeframe: '1D', count: 370),
        _ => (timeframe: '1D', count: 32),
      };
    }
    return (timeframe: '1h', count: 48);
  }
}
