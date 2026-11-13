import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/equity_data_source.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/market/routing_market_data_client.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';

import 'support/memory_config.dart';

class _FakeEquityClient implements MarketDataClient {
  var calls = 0;
  final requested = <List<String>>[];

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    calls += 1;
    requested.add(List<String>.from(symbols));
    return [
      for (final s in symbols)
        Quote(symbol: s, price: 10, dataSourceId: 'yahoo'),
    ];
  }
}

class _FakeCryptoClient extends CryptoExchangeClient {
  _FakeCryptoClient({required this.id});

  final String id;
  var calls = 0;
  final requested = <List<String>>[];

  @override
  CryptoExchange get exchange => CryptoExchange(
        id: id,
        displayName: id,
        defaultSymbols: const ['BTC_USD'],
      );

  @override
  bool handlesSymbol(String symbol) => symbol.contains('_');

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    calls += 1;
    requested.add(List<String>.from(symbols));
    return [
      for (final s in symbols)
        Quote(symbol: s, price: 20, dataSourceId: id),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routes equities and crypto symbols to the right clients', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();

    final equity = _FakeEquityClient();
    final crypto = _FakeCryptoClient(id: 'crypto_com');
    final router = RoutingMarketDataClient(
      equitiesRegistry: EquityDataSourceRegistry([
        EquityDataSourceEntry(
          source: const EquityDataSource(id: 'yahoo', displayName: 'Yahoo'),
          client: equity,
        ),
      ]),
      cryptoRegistry: CryptoExchangeRegistry([crypto]),
      dataSources: dataSources,
    );

    final quotes = await router.getQuotes(const ['AAPL', 'BTC_USD', 'MSFT']);
    expect(quotes.map((q) => q.symbol), containsAll(['AAPL', 'BTC_USD', 'MSFT']));
    expect(equity.calls, 1);
    expect(equity.requested.single, ['AAPL', 'MSFT']);
    expect(crypto.calls, 1);
    expect(crypto.requested.single, ['BTC_USD']);
  });

  test('skips disabled crypto venues', () async {
    final store = await memoryConfig();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    await dataSources.setCryptoEnabled('crypto_com', false);

    final equity = _FakeEquityClient();
    final crypto = _FakeCryptoClient(id: 'crypto_com');
    final router = RoutingMarketDataClient(
      equitiesRegistry: EquityDataSourceRegistry([
        EquityDataSourceEntry(
          source: const EquityDataSource(id: 'yahoo', displayName: 'Yahoo'),
          client: equity,
        ),
      ]),
      cryptoRegistry: CryptoExchangeRegistry([crypto]),
      dataSources: dataSources,
    );

    final quotes = await router.getQuotes(const ['BTC_USD']);
    expect(crypto.calls, 0);
    expect(equity.calls, 1);
    expect(quotes.single.symbol, 'BTC_USD');
  });
}
