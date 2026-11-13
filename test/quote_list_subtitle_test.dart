import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/models.dart';

void main() {
  test('listSubtitle prefers name and appends exchange', () {
    const quote = Quote(
      symbol: 'AAPL',
      price: 190,
      name: 'Apple Inc.',
      exchange: 'NasdaqGS',
    );
    expect(quote.listSubtitle, 'Apple Inc. · NasdaqGS');
  });

  test('listSubtitle formats underscore pairs when name is only the base', () {
    const quote = Quote(
      symbol: 'BTC_USD',
      price: 1,
      name: 'BTC',
      exchange: 'Crypto.com',
    );
    expect(quote.listSubtitle, 'BTC / USD · Crypto.com');
  });

  test('listSubtitle uses pair label when name is absent', () {
    const quote = Quote(
      symbol: 'ETH_USDT',
      price: 1,
    );
    expect(quote.listSubtitle, 'ETH / USDT');
  });

  test('listSubtitle is null when only the ticker is known', () {
    const quote = Quote(symbol: 'XYZ', price: 1);
    expect(quote.listSubtitle, isNull);
  });

  test('listSubtitle skips name that duplicates the symbol', () {
    const quote = Quote(
      symbol: 'AAPL',
      price: 1,
      name: 'aapl',
      exchange: 'NYSE',
    );
    expect(quote.listSubtitle, 'NYSE');
  });
}
