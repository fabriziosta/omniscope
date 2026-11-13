import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/asset_overviews.dart';

void main() {
  group('assetOverview', () {
    test('returns blurbs for default watchlist symbols', () {
      expect(assetOverview('AAPL'), contains('Apple'));
      expect(assetOverview('^GSPC'), contains('S&P 500'));
      expect(assetOverview('SPY'), contains('ETF'));
      expect(assetOverview('BTC_USD'), contains('Bitcoin'));
    });

    test('normalizes case and whitespace', () {
      expect(assetOverview(' aapl '), assetOverview('AAPL'));
      expect(assetOverview('btc_usd'), assetOverview('BTC_USD'));
    });

    test('returns null for unknown or blank symbols', () {
      expect(assetOverview('ZZZZ'), isNull);
      expect(assetOverview(''), isNull);
      expect(assetOverview('   '), isNull);
    });
  });
}
