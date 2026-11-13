import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/features/quotes/quotes_list_controller.dart';

class _FakeMarketDataClient implements MarketDataClient {
  _FakeMarketDataClient({this.delay = Duration.zero, this.fail = false});

  Duration delay;
  bool fail;
  var calls = 0;
  final requestedBatches = <List<String>>[];

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
    requestedBatches.add(List<String>.from(symbols));
    final call = calls;
    await Future<void>.delayed(delay);
    if (fail) throw Exception('network');
    return [
      for (final s in symbols)
        Quote(symbol: s, price: 10.0 * call, name: s),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh loads first page only', () async {
    final client = _FakeMarketDataClient();
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
    final client = _FakeMarketDataClient();
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
    final client = _FakeMarketDataClient(fail: true);
    final controller = QuotesListController(
      client: client,
      symbols: const ['AAPL'],
    );

    await controller.refresh();

    expect(controller.hasError, isTrue);
    expect(controller.error, isNotNull);
    expect(controller.quotes, isEmpty);
  });

  test('stale refresh is ignored when a newer load wins', () async {
    final client = _FakeMarketDataClient(
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
}
