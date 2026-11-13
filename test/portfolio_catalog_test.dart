import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/crypto/exchange_portfolio.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_catalog.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/order_models.dart';

import 'support/memory_config.dart';

class _NoLiveClient implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = const CryptoExchange(
    id: 'no_live',
    displayName: 'No Live',
    defaultSymbols: ['BTC_USD'],
  );

  @override
  bool get supportsLivePortfolio => false;

  @override
  bool get canFetchPortfolio => false;

  @override
  bool handlesSymbol(String symbol) => false;

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => const [];

  @override
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    throw UnsupportedError('no live portfolio');
  }

  @override
  bool get supportsLiveTrading => false;

  @override
  bool get canPlaceOrders => false;

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> cancelOrder(String orderId) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> getOrder(String orderId) async =>
      const OrderResult.fail('not supported');
}

class _PendingLiveClient implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = CryptoComExchangeClient.meta;

  @override
  bool get supportsLivePortfolio => true;

  @override
  bool get canFetchPortfolio => false;

  @override
  bool handlesSymbol(String symbol) => false;

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => const [];

  @override
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    throw UnsupportedError('pending credentials');
  }

  @override
  bool get supportsLiveTrading => false;

  @override
  bool get canPlaceOrders => false;

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> cancelOrder(String orderId) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> getOrder(String orderId) async =>
      const OrderResult.fail('not supported');
}

class _ReadyLiveClient implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = CryptoComExchangeClient.meta;

  @override
  bool get supportsLivePortfolio => true;

  @override
  bool get canFetchPortfolio => true;

  @override
  bool handlesSymbol(String symbol) => false;

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => const [];

  @override
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    return ExchangePortfolioSnapshot(
      exchangeId: exchange.id,
      exchangeName: exchange.displayName,
      balances: const [],
    );
  }

  @override
  bool get supportsLiveTrading => false;

  @override
  bool get canPlaceOrders => false;

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> cancelOrder(String orderId) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> getOrder(String orderId) async =>
      const OrderResult.fail('not supported');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('list returns Practice only when no live clients are ready', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();

    final listed = PortfolioCatalog.list(
      registry: CryptoExchangeRegistry([_NoLiveClient(), _PendingLiveClient()]),
      dataSources: dataSources,
    );

    expect(listed, hasLength(1));
    expect(listed.single.id, PortfolioDescriptor.practiceId);
    expect(listed.single.isPractice, isTrue);
  });

  test('list includes ready live exchange after Practice', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();

    final listed = PortfolioCatalog.list(
      registry: CryptoExchangeRegistry([_ReadyLiveClient()]),
      dataSources: dataSources,
    );

    expect(listed, hasLength(2));
    expect(listed[0].isPractice, isTrue);
    expect(listed[1].id, CryptoComExchangeClient.meta.id);
    expect(listed[1].displayName, CryptoComExchangeClient.meta.displayName);
    expect(listed[1].isLive, isTrue);
  });

  test('includePendingLive adds credential-pending venues', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();

    final listed = PortfolioCatalog.list(
      registry: CryptoExchangeRegistry([_PendingLiveClient()]),
      dataSources: dataSources,
      includePendingLive: true,
    );

    expect(listed, hasLength(2));
    expect(listed[0].isPractice, isTrue);
    expect(listed[1].id, CryptoComExchangeClient.meta.id);
    expect(listed[1].isLive, isTrue);
  });

  test('disabled crypto venue is omitted even when ready', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    await dataSources.setCryptoEnabled(CryptoComExchangeClient.meta.id, false);

    final listed = PortfolioCatalog.list(
      registry: CryptoExchangeRegistry([_ReadyLiveClient()]),
      dataSources: dataSources,
      includePendingLive: true,
    );

    expect(listed, hasLength(1));
    expect(listed.single.isPractice, isTrue);
  });

  test('Crypto.com client unlocks live when key and secret are set', () {
    final client = CryptoComExchangeClient(
      credentials: const ExchangeCredentials(
        apiKey: 'k',
        apiSecret: 's',
      ),
    );
    expect(client.supportsLivePortfolio, isTrue);
    expect(client.canFetchPortfolio, isTrue);
  });
}
