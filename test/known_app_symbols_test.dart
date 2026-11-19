import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/known_app_symbols.dart';
import 'package:omniscope/data/market/models.dart';

void main() {
  group('matchingKnownSymbolsInText', () {
    test('matches exact known tokens only', () {
      final known = {
        'AAPL',
        'MSFT',
        'BTC_USD',
        ...defaultWatchlist.map((s) => s.toUpperCase()),
      };

      expect(
        matchingKnownSymbolsInText(
          'Investigate AAPL.',
          known: known,
        ),
        ['AAPL'],
      );
      expect(
        matchingKnownSymbolsInText(
          'Compare MSFT and AAPL today.',
          known: known,
        ),
        ['AAPL', 'MSFT'],
      );
      expect(
        matchingKnownSymbolsInText(
          'Look at BTC_USD spot.',
          known: known,
        ),
        ['BTC_USD'],
      );
      expect(
        matchingKnownSymbolsInText(
          'No ticker here — just words like AND OR BUY.',
          known: known,
        ),
        isEmpty,
      );
      expect(
        matchingKnownSymbolsInText(
          'Ignore SYMBOL placeholders.',
          known: known,
        ),
        isEmpty,
      );
    });

    test('prefers longer exact symbols over prefixes', () {
      final known = {'BTC', 'BTC_USD'};
      expect(
        matchingKnownSymbolsInText('Check BTC_USD please.', known: known),
        ['BTC_USD'],
      );
    });
  });
}
