import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/features/quotes/quotes_list_controller.dart';

import 'support/fake_market_data_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh loads first page only', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final symbols = [for (var i = 0; i < 40; i++) 'S$i'];
    final controller = QuotesListController(
      client: client,
      symbols: symbols,
      pageSize: 10,
    );

    await controller.refresh();

    expect(controller.loading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.quotes, hasLength(10));
    expect(controller.hasMore, isTrue);
    expect(controller.fetchedCount, 10);
    expect(client.requestedBatches.single, symbols.take(10).toList());
  });

  test('loadMore appends the next page', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final symbols = [for (var i = 0; i < 25; i++) 'S$i'];
    final controller = QuotesListController(
      client: client,
      symbols: symbols,
      pageSize: 10,
    );

    await controller.refresh();
    await controller.loadMore();
    await controller.loadMore();

    expect(controller.quotes, hasLength(25));
    expect(controller.hasMore, isFalse);
    expect(client.calls, 3);
    expect(client.requestedBatches[1], symbols.skip(10).take(10).toList());
    expect(client.requestedBatches[2], symbols.skip(20).take(10).toList());
  });

  test('refresh sets friendly error on failure', () async {
    final client = FakeMarketDataClient(fail: true);
    final controller = QuotesListController(
      client: client,
      symbols: const ['AAPL'],
    );

    await controller.refresh();

    expect(controller.hasError, isTrue);
    expect(controller.error, isNotNull);
    expect(controller.quotes, isEmpty);
  });

  test('loadMore soft-fails without clearing existing quotes', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final symbols = [for (var i = 0; i < 20; i++) 'S$i'];
    final controller = QuotesListController(
      client: client,
      symbols: symbols,
      pageSize: 10,
    );

    await controller.refresh();
    expect(controller.quotes, hasLength(10));
    expect(controller.fetchedAt, isNotNull);

    client.fail = true;
    await controller.loadMore();

    expect(controller.quotes, hasLength(10));
    expect(controller.hasError, isFalse);
    expect(controller.lastPagingError, isNotNull);
    expect(controller.loadingMore, isFalse);

    controller.clearPagingError();
    expect(controller.lastPagingError, isNull);
  });

  test('stale refresh is ignored when a newer load wins', () async {
    final client = FakeMarketDataClient(
      basePrice: 10,
      scalePriceByCall: true,
      delay: const Duration(milliseconds: 40),
    );
    final controller = QuotesListController(
      client: client,
      symbols: const ['AAPL'],
    );

    final first = controller.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    client.delay = Duration.zero;
    await controller.refresh();
    await first;

    expect(controller.quotes.single.price, 20);
    expect(client.calls, 2);
  });

  test('setSymbolQuery fetches only matching catalog symbols', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final controller = QuotesListController(
      client: client,
      symbols: const [
        'ETH_USD',
        'BTC_USD',
        'SOL_USD',
        'WBTC_USD',
        'ADA_USD',
        'BTC_EUR',
      ],
      pageSize: 10,
    );

    await controller.refresh();
    expect(client.requestedBatches.single, [
      'ETH_USD',
      'BTC_USD',
      'SOL_USD',
      'WBTC_USD',
      'ADA_USD',
      'BTC_EUR',
    ]);

    await controller.setSymbolQuery('BTC');

    expect(controller.symbolQuery, 'btc');
    expect(controller.totalSymbols, 3);
    expect(controller.hasMore, isFalse);
    expect(
      controller.quotes.map((q) => q.symbol),
      ['BTC_USD', 'WBTC_USD', 'BTC_EUR'],
    );
    expect(client.requestedBatches.last, [
      'BTC_USD',
      'WBTC_USD',
      'BTC_EUR',
    ]);
  });

  test('loadMore under query pages further matches only', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final symbols = [
      for (var i = 0; i < 10; i++) 'ETH_$i',
      for (var i = 0; i < 25; i++) 'BTC_$i',
      for (var i = 0; i < 10; i++) 'SOL_$i',
    ];
    final controller = QuotesListController(
      client: client,
      symbols: symbols,
      pageSize: 10,
    );

    await controller.setSymbolQuery('BTC');
    expect(controller.totalSymbols, 25);
    expect(controller.quotes, hasLength(10));
    expect(controller.hasMore, isTrue);
    expect(
      client.requestedBatches.single,
      [for (var i = 0; i < 10; i++) 'BTC_$i'],
    );

    await controller.loadMore();
    expect(controller.quotes, hasLength(20));
    expect(
      client.requestedBatches[1],
      [for (var i = 10; i < 20; i++) 'BTC_$i'],
    );

    await controller.loadMore();
    expect(controller.quotes, hasLength(25));
    expect(controller.hasMore, isFalse);
    expect(
      client.requestedBatches[2],
      [for (var i = 20; i < 25; i++) 'BTC_$i'],
    );
  });

  test('clearing symbol query restores full-catalog browse paging', () async {
    final client = FakeMarketDataClient(basePrice: 10, scalePriceByCall: true);
    final symbols = [
      for (var i = 0; i < 5; i++) 'ETH_$i',
      for (var i = 0; i < 5; i++) 'BTC_$i',
      for (var i = 0; i < 20; i++) 'SOL_$i',
    ];
    final controller = QuotesListController(
      client: client,
      symbols: symbols,
      pageSize: 10,
    );

    await controller.setSymbolQuery('BTC');
    expect(controller.quotes, hasLength(5));

    await controller.setSymbolQuery('');
    expect(controller.symbolQuery, isEmpty);
    expect(controller.totalSymbols, 30);
    expect(controller.quotes, hasLength(10));
    expect(controller.hasMore, isTrue);
    expect(client.requestedBatches.last, symbols.take(10).toList());
  });

  test('query with zero matches yields empty quotes', () async {
    final client = FakeMarketDataClient(basePrice: 10);
    final controller = QuotesListController(
      client: client,
      symbols: const ['ETH_USD', 'SOL_USD'],
      pageSize: 10,
    );

    await controller.setSymbolQuery('BTC');

    expect(controller.symbolQuery, 'btc');
    expect(controller.totalSymbols, 0);
    expect(controller.quotes, isEmpty);
    expect(controller.hasMore, isFalse);
    expect(controller.hasLoaded, isTrue);
    expect(controller.hasError, isFalse);
    expect(client.calls, 0);
  });
}
