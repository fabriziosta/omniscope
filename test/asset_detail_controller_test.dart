import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/features/asset_detail/asset_detail_controller.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load populates quote and candles', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final client = FakeMarketDataClient(scalePriceByCall: true);
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
    expect(controller.fetchedAt, isNotNull);
    expect(AssetDetailController.rangeExplainer('1M'), contains('month'));
  });

  test('stale load is ignored when a newer load wins', () async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final client = FakeMarketDataClient(
      scalePriceByCall: true,
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
      marketData: FakeMarketDataClient(scalePriceByCall: true),
      portfolio: portfolio,
      initialRange: ChartRangePreset.oneMonth,
    );
    await controller.load();

    final result = await controller.trade(buy: true, sharesText: 'abc');
    expect(result, isNull);
  });
}
