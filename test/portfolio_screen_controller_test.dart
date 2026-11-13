import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/features/portfolio/portfolio_screen_controller.dart';

import 'support/memory_config.dart';

class _FakeMarketDataClient implements MarketDataClient {
  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => [
        for (final s in symbols) Quote(symbol: s, price: 200, name: s),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mark-to-market helpers use quote prices when available', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    await portfolio.buy(symbol: 'AAPL', shares: 2, price: 100);

    final controller = PortfolioScreenController(
      marketData: _FakeMarketDataClient(),
      portfolio: portfolio,
      cryptoRegistry: CryptoExchangeRegistry(const []),
      dataSources: DataSourceSettings(store: store),
    );

    await controller.refreshQuotes();

    final state = portfolio.state;
    expect(controller.holdingsValueFor(state), 400);
    expect(controller.costBasisFor(state), 200);
    expect(controller.unrealizedFor(state), 200);
    expect(controller.paperTotalFor(state), state.cash + 400);
  });

  test('refreshQuotes clears when there are no holdings', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();

    final controller = PortfolioScreenController(
      marketData: _FakeMarketDataClient(),
      portfolio: portfolio,
      cryptoRegistry: CryptoExchangeRegistry(const []),
      dataSources: DataSourceSettings(store: store),
    );

    await controller.refreshQuotes();
    expect(controller.quotes, isEmpty);
    expect(controller.quoteError, isNull);
    expect(controller.loadingQuotes, isFalse);
  });
}
