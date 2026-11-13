import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/features/asset_detail/asset_detail_controller.dart';

import 'support/memory_config.dart';

class _FakeMarketDataClient implements MarketDataClient {
  _FakeMarketDataClient({this.delay = Duration.zero});

  Duration delay;
  var quoteCalls = 0;

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    await Future<void>.delayed(delay);
    return [
      Candle(time: DateTime.utc(2026, 1, 1), close: 100),
      Candle(time: DateTime.utc(2026, 1, 2), close: 110),
    ];
  }

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    quoteCalls += 1;
    final price = 100.0 * quoteCalls;
    await Future<void>.delayed(delay);
    return [
      for (final s in symbols) Quote(symbol: s, price: price, name: s),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load populates quote and candles', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final client = _FakeMarketDataClient();
    final controller = AssetDetailController(
      symbol: 'AAPL',
      marketData: client,
      portfolio: portfolio,
      initialRange: ChartRangePreset.oneMonth,
    );

    await controller.load();

    expect(controller.loading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.quote?.price, 100);
    expect(controller.candles, hasLength(2));
  });

  test('stale load is ignored when a newer load wins', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final client = _FakeMarketDataClient(
      delay: const Duration(milliseconds: 40),
    );
    final controller = AssetDetailController(
      symbol: 'AAPL',
      marketData: client,
      portfolio: portfolio,
      initialRange: ChartRangePreset.oneMonth,
    );

    final first = controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    client.delay = Duration.zero;
    await controller.load();
    await first;

    expect(controller.quote?.price, 200);
    expect(client.quoteCalls, 2);
  });

  test('trade returns null for invalid quantity', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final controller = AssetDetailController(
      symbol: 'AAPL',
      marketData: _FakeMarketDataClient(),
      portfolio: portfolio,
      initialRange: ChartRangePreset.oneMonth,
    );
    await controller.load();

    final result = await controller.trade(buy: true, sharesText: 'abc');
    expect(result, isNull);
  });
}
