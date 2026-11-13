import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/caching_market_data_client.dart';
import 'package:omniscope/data/market/models.dart';

import 'support/fake_market_data_client.dart';

void main() {
  test('serves warm quotes from memory without a second inner call', () async {
    final inner = FakeMarketDataClient(basePrice: 42);
    final cache = CachingMarketDataClient(
      inner,
      quoteTtl: const Duration(seconds: 30),
    );

    final first = await cache.getQuotes(const ['AAPL', 'MSFT']);
    final second = await cache.getQuotes(const ['AAPL', 'MSFT']);

    expect(first.map((q) => q.price), [42.0, 42.0]);
    expect(second.map((q) => q.price), [42.0, 42.0]);
    expect(inner.quoteCalls, 1);
    expect(inner.requestedBatches, [
      ['AAPL', 'MSFT'],
    ]);
  });

  test('fetches only missing symbols on a partial cache hit', () async {
    final inner = FakeMarketDataClient(basePrice: 10);
    final cache = CachingMarketDataClient(inner);

    await cache.getQuotes(const ['AAPL']);
    expect(inner.quoteCalls, 1);

    final mixed = await cache.getQuotes(const ['AAPL', 'MSFT']);
    expect(mixed.map((q) => q.symbol), ['AAPL', 'MSFT']);
    expect(inner.quoteCalls, 2);
    expect(inner.requestedBatches.last, ['MSFT']);
  });

  test('coalesces concurrent quote requests for the same batch', () async {
    final inner = FakeMarketDataClient(
      basePrice: 7,
      delay: const Duration(milliseconds: 40),
    );
    final cache = CachingMarketDataClient(inner);

    final results = await Future.wait([
      cache.getQuotes(const ['AAPL']),
      cache.getQuotes(const ['AAPL']),
      cache.getQuotes(const ['AAPL']),
    ]);

    expect(inner.quoteCalls, 1);
    for (final batch in results) {
      expect(batch.single.price, 7);
    }
  });

  test('refetches quotes after TTL expires', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final inner = FakeMarketDataClient(basePrice: 1, scalePriceByCall: true);
    final cache = CachingMarketDataClient(
      inner,
      quoteTtl: const Duration(seconds: 30),
      clock: () => now,
    );

    expect((await cache.getQuotes(const ['AAPL'])).single.price, 1);
    now = now.add(const Duration(seconds: 31));
    expect((await cache.getQuotes(const ['AAPL'])).single.price, 2);
    expect(inner.quoteCalls, 2);
  });

  test('caches history by symbol range and interval', () async {
    var historyCalls = 0;
    final candles = [
      Candle(time: DateTime.utc(2026, 1, 1), close: 100),
      Candle(time: DateTime.utc(2026, 1, 2), close: 110),
    ];
    final inner = FakeMarketDataClient(
      historyBuilder: (_) {
        historyCalls += 1;
        return candles;
      },
    );
    final cache = CachingMarketDataClient(
      inner,
      historyTtl: const Duration(minutes: 10),
    );

    final first = await cache.getHistory(
      'AAPL',
      range: '1mo',
      interval: '1d',
    );
    final second = await cache.getHistory(
      'AAPL',
      range: '1mo',
      interval: '1d',
    );
    await cache.getHistory('AAPL', range: '3mo', interval: '1d');

    expect(first, candles);
    expect(second, candles);
    expect(historyCalls, 2); // 1mo cached; 3mo is a different key
  });

  test('coalesces concurrent history requests', () async {
    var historyCalls = 0;
    final inner = FakeMarketDataClient(
      delay: const Duration(milliseconds: 40),
      historyBuilder: (_) {
        historyCalls += 1;
        return [
          Candle(time: DateTime.utc(2026, 1, 1), close: 50),
        ];
      },
    );
    final cache = CachingMarketDataClient(inner);

    final results = await Future.wait([
      cache.getHistory('AAPL', range: '1mo', interval: '1d'),
      cache.getHistory('AAPL', range: '1mo', interval: '1d'),
    ]);

    expect(historyCalls, 1);
    expect(results[0].single.close, 50);
    expect(results[1].single.close, 50);
  });
}
