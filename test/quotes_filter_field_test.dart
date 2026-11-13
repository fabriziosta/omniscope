import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/widgets/quotes_filter_field.dart';

void main() {
  test('filterBySymbolQuery matches symbol and name', () {
    const quotes = [
      Quote(symbol: 'BTC_USD', price: 1, name: 'Bitcoin'),
      Quote(symbol: 'ETH_USD', price: 2, name: 'Ethereum'),
      Quote(symbol: 'AAPL', price: 3, name: 'Apple'),
    ];

    final bySymbol = filterBySymbolQuery(
      items: quotes,
      query: 'btc',
      symbolOf: (q) => q.symbol,
      nameOf: (q) => q.name,
    );
    expect(bySymbol.map((q) => q.symbol), ['BTC_USD']);

    final byName = filterBySymbolQuery(
      items: quotes,
      query: 'apple',
      symbolOf: (q) => q.symbol,
      nameOf: (q) => q.name,
    );
    expect(byName.map((q) => q.symbol), ['AAPL']);

    final empty = filterBySymbolQuery(
      items: quotes,
      query: '   ',
      symbolOf: (q) => q.symbol,
      nameOf: (q) => q.name,
    );
    expect(empty, hasLength(3));
  });
}
