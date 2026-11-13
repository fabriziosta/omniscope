import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../market/exchange_credentials.dart';
import '../../trading/broker_exchange.dart';
import '../../trading/broker_exchange_client.dart';
import '../../trading/order_models.dart';
import '../../venues/exchange_portfolio.dart';
import '../../venues/http/venue_http.dart';
import '../../venues/venue_credential_schema.dart';
import 'alpaca_auth.dart';
import 'alpaca_broker.dart';
import 'alpaca_dto.dart';

/// Alpaca Trading API adapter (paper + live).
///
/// Equities market data stays on [MarketDataClient] (Yahoo). This client only
/// handles private portfolio + orders once API key and secret are configured
/// under Settings → Data sources.
///
/// - Paper: `https://paper-api.alpaca.markets`
/// - Live: `https://api.alpaca.markets`
class AlpacaExchangeClient extends BrokerExchangeClient {
  AlpacaExchangeClient({
    http.Client? httpClient,
    ExchangeCredentials credentials = ExchangeCredentials.empty,
  })  : _credentials = credentials,
        _http = httpClient ?? http.Client();
  static BrokerExchange get meta => AlpacaBroker.meta;

  static VenueCredentialSchema get credentialSchema =>
      AlpacaBroker.credentialSchema;

  final http.Client _http;
  ExchangeCredentials _credentials;

  @override
  BrokerExchange get broker => meta;

  @override
  ExchangeCredentials get credentials => _credentials;

  @override
  void setCredentials(ExchangeCredentials value) {
    _credentials = value;
  }

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

  String get _base => AlpacaAuth.baseUrlFor(credentials);

  Map<String, String> get _headers => AlpacaAuth.headers(credentials);

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    if (!canFetchPortfolio) {
      throw StateError('Alpaca credentials are not configured');
    }

    final accountRes = await _http.get(
      Uri.parse('$_base/v2/account'),
      headers: _headers,
    );
    if (!VenueHttp.isSuccessStatus(accountRes.statusCode)) {
      throw StateError(
        'Alpaca account failed: HTTP ${accountRes.statusCode}',
      );
    }
    final account = VenueHttp.decodeObject(accountRes);
    if (account == null) {
      throw StateError('Alpaca account response was empty');
    }

    final positionsRes = await _http.get(
      Uri.parse('$_base/v2/positions'),
      headers: _headers,
    );
    if (!VenueHttp.isSuccessStatus(positionsRes.statusCode)) {
      throw StateError(
        'Alpaca positions failed: HTTP ${positionsRes.statusCode}',
      );
    }
    final positions = VenueHttp.decodeList(positionsRes);

    return AlpacaDto.portfolioFromAccountAndPositions(
      exchangeId: meta.id,
      exchangeName: meta.displayName,
      account: account,
      positions: positions,
    );
  }

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail('Alpaca credentials are not configured');
    }
    try {
      final res = await _http.post(
        Uri.parse('$_base/v2/orders'),
        headers: _headers,
        body: jsonEncode(AlpacaDto.placeOrderBody(request)),
      );
      if (!VenueHttp.isSuccessStatus(res.statusCode)) {
        return VenueHttp.failFromResponse(res, fallback: 'Order rejected');
      }
      final json = VenueHttp.decodeObject(res);
      if (json == null) {
        return const OrderResult.fail('Empty Alpaca order response');
      }
      return AlpacaDto.orderResultFromJson(json);
    } catch (e, st) {
      developer.log(
        'Alpaca placeOrder failed: $e',
        name: 'AlpacaExchangeClient',
        stackTrace: st,
      );
      return OrderResult.fail(e.toString());
    }
  }

  @override
  Future<OrderResult> cancelOrder(String orderId) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail('Alpaca credentials are not configured');
    }
    final id = orderId.trim();
    if (id.isEmpty) {
      return const OrderResult.fail('Missing order id');
    }
    try {
      final res = await _http.delete(
        Uri.parse('$_base/v2/orders/$id'),
        headers: _headers,
      );
      // Alpaca returns 204 on success.
      if (res.statusCode == 204 || VenueHttp.isSuccessStatus(res.statusCode)) {
        return OrderResult.ok(orderId: id, rawStatus: 'canceled');
      }
      return VenueHttp.failFromResponse(res, fallback: 'Cancel failed');
    } catch (e, st) {
      developer.log(
        'Alpaca cancelOrder failed: $e',
        name: 'AlpacaExchangeClient',
        stackTrace: st,
      );
      return OrderResult.fail(e.toString());
    }
  }

  @override
  Future<OrderResult> getOrder(String orderId) async {
    if (!canPlaceOrders) {
      return const OrderResult.fail('Alpaca credentials are not configured');
    }
    final id = orderId.trim();
    if (id.isEmpty) {
      return const OrderResult.fail('Missing order id');
    }
    try {
      final res = await _http.get(
        Uri.parse('$_base/v2/orders/$id'),
        headers: _headers,
      );
      if (!VenueHttp.isSuccessStatus(res.statusCode)) {
        return VenueHttp.failFromResponse(res, fallback: 'Get order failed');
      }
      final json = VenueHttp.decodeObject(res);
      if (json == null) {
        return const OrderResult.fail('Empty Alpaca order response');
      }
      return AlpacaDto.orderResultFromJson(json);
    } catch (e, st) {
      developer.log(
        'Alpaca getOrder failed: $e',
        name: 'AlpacaExchangeClient',
        stackTrace: st,
      );
      return OrderResult.fail(e.toString());
    }
  }
}
