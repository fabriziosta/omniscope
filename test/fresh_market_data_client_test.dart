import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/caching_market_data_client.dart';
import 'package:omniscope/data/market/fresh_market_data_client.dart';

import 'support/fake_market_data_client.dart';

void main() {
  test('FreshMarketDataClient bypasses CachingMarketDataClient TTL', () async {
    final inner = FakeMarketDataClient(
      basePrice: 10,
      scalePriceByCall: true,
    );
    final cache = CachingMarketDataClient(
      inner,
      quoteTtl: const Duration(hours: 1),
    );
    final fresh = FreshMarketDataClient(cache);

    final cachedFirst = await cache.getQuotes(const ['AAPL']);
    expect(cachedFirst.single.price, 10);
    expect(inner.quoteCalls, 1);

    final warm = await cache.getQuotes(const ['AAPL']);
    expect(warm.single.price, 10);
    expect(inner.quoteCalls, 1);

    final freshQuotes = await fresh.getQuotes(const ['AAPL']);
    expect(freshQuotes.single.price, 20);
    expect(inner.quoteCalls, 2);

    // UI cache still holds the first fetch.
    final stillWarm = await cache.getQuotes(const ['AAPL']);
    expect(stillWarm.single.price, 10);
    expect(inner.quoteCalls, 2);
  });

  test('FreshMarketDataClient coalesces concurrent quote batches', () async {
    final inner = FakeMarketDataClient(
      basePrice: 7,
      delay: const Duration(milliseconds: 40),
    );
    final fresh = FreshMarketDataClient(inner);

    final results = await Future.wait([
      fresh.getQuotes(const ['AAPL']),
      fresh.getQuotes(const ['AAPL']),
      fresh.getQuotes(const ['AAPL']),
    ]);

    expect(inner.quoteCalls, 1);
    for (final batch in results) {
      expect(batch.single.price, 7);
    }
  });

  test('unwraps nested CachingMarketDataClient to the router', () async {
    final inner = FakeMarketDataClient(basePrice: 3);
    final cache = CachingMarketDataClient(inner);
    final fresh = FreshMarketDataClient(cache);
    expect(identical(cache.inner, inner), isTrue);

    await fresh.getQuotes(const ['MSFT']);
    expect(inner.quoteCalls, 1);
  });
}
