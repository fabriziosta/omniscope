import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/market_context_builder.dart';

import 'support/fake_market_data_client.dart';

void main() {
  test('buildForSymbol includes fetched-at stamp and quote fields', () async {
    final client = FakeMarketDataClient(
      basePrice: 150,
      previousClose: 148,
      changePercent: 0.0135,
      fixedName: 'Apple Inc.',
      exchange: 'NMS',
      dataSource: 'Yahoo Finance',
    );
    final builder = MarketContextBuilder(client);
    final text = await builder.buildForSymbol(
      'aapl',
      fetchedAt: DateTime.utc(2026, 6, 1, 12),
    );

    expect(text, isNotNull);
    expect(
      text!,
      contains('Market snapshot (fetched 2026-06-01T12:00:00.000Z)'),
    );
    expect(text, contains('for AAPL'));
    expect(text, contains('Apple Inc.'));
    expect(text, contains('NMS'));
    expect(text, contains('Yahoo Finance'));
    expect(text, contains('~1M range closes'));
    expect(text, contains('getQuotes/getHistory'));
  });

  test('buildForSymbol returns null when quote and history fail empty', () async {
    final client = FakeMarketDataClient(emptyQuotes: true, emptyHistory: true);
    final text = await MarketContextBuilder(client).buildForSymbol('ZZZ');
    expect(text, isNull);
  });
}
