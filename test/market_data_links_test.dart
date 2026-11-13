import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/market_data_links.dart';

void main() {
  group('publicMarketPageUrl', () {
    test('builds Yahoo quote URL with encoded symbol', () {
      final uri = publicMarketPageUrl(
        symbol: '^GSPC',
        dataSourceId: 'yahoo',
      );
      expect(uri?.toString(), 'https://finance.yahoo.com/quote/%5EGSPC');
    });

    test('builds Crypto.com trade URL', () {
      final uri = publicMarketPageUrl(
        symbol: 'BTC_USD',
        dataSourceId: 'crypto_com',
      );
      expect(uri?.toString(), 'https://crypto.com/exchange/trade/BTC_USD');
    });

    test('returns null for unknown or empty source', () {
      expect(
        publicMarketPageUrl(symbol: 'AAPL', dataSourceId: null),
        isNull,
      );
      expect(
        publicMarketPageUrl(symbol: 'AAPL', dataSourceId: 'other'),
        isNull,
      );
      expect(
        publicMarketPageUrl(symbol: '', dataSourceId: 'yahoo'),
        isNull,
      );
    });
  });

  group('googleFinanceUrl', () {
    test('maps Nasdaq equity with Yahoo exchange code', () {
      final uri = googleFinanceUrl(symbol: 'AAPL', exchange: 'NMS');
      expect(
        uri.toString(),
        'https://www.google.com/finance/quote/AAPL:NASDAQ',
      );
    });

    test('maps Yahoo .DE suffix to ETR', () {
      final uri = googleFinanceUrl(symbol: 'SAP.DE');
      expect(
        uri.toString(),
        'https://www.google.com/finance/quote/SAP:ETR',
      );
    });

    test('maps S&P 500 index', () {
      final uri = googleFinanceUrl(symbol: '^GSPC');
      expect(
        uri.toString(),
        'https://www.google.com/finance/quote/.INX:INDEXSP',
      );
    });

    test('maps crypto pair to hyphenated quote', () {
      final uri = googleFinanceUrl(symbol: 'BTC_USD');
      expect(
        uri.toString(),
        'https://www.google.com/finance/quote/BTC-USD',
      );
    });

    test('falls back to search for unmapped symbols', () {
      final uri = googleFinanceUrl(symbol: 'EURUSD=X');
      expect(
        uri.toString(),
        'https://www.google.com/finance/search?q=EURUSD%3DX',
      );
    });
  });

  group('tradingViewUrl', () {
    test('maps Nasdaq equity with Yahoo exchange code', () {
      final uri = tradingViewUrl(symbol: 'AAPL', exchange: 'NMS');
      expect(
        uri.toString(),
        'https://www.tradingview.com/chart/?symbol=NASDAQ%3AAAPL',
      );
    });

    test('maps Yahoo .DE suffix to XETR', () {
      final uri = tradingViewUrl(symbol: 'SAP.DE');
      expect(
        uri.toString(),
        'https://www.tradingview.com/chart/?symbol=XETR%3ASAP',
      );
    });

    test('maps S&P 500 index', () {
      final uri = tradingViewUrl(symbol: '^GSPC');
      expect(
        uri.toString(),
        'https://www.tradingview.com/chart/?symbol=SP%3ASPX',
      );
    });

    test('maps crypto pair to CRYPTO prefix', () {
      final uri = tradingViewUrl(symbol: 'BTC_USD');
      expect(
        uri.toString(),
        'https://www.tradingview.com/chart/?symbol=CRYPTO%3ABTCUSD',
      );
    });
  });

  group('wikipediaUrl', () {
    test('maps curated equity to Wikipedia article', () {
      expect(
        wikipediaUrl(symbol: 'AAPL')?.toString(),
        'https://en.wikipedia.org/wiki/Apple_Inc.',
      );
    });

    test('encodes ampersand in index titles', () {
      expect(
        wikipediaUrl(symbol: '^GSPC')?.toString(),
        'https://en.wikipedia.org/wiki/S%26P_500',
      );
    });

    test('maps crypto pairs to coin articles', () {
      expect(
        wikipediaUrl(symbol: 'BTC_USD')?.toString(),
        'https://en.wikipedia.org/wiki/Bitcoin',
      );
    });

    test('returns null for unmapped symbols', () {
      expect(wikipediaUrl(symbol: 'ZZZZ'), isNull);
      expect(wikipediaUrl(symbol: '  '), isNull);
    });
  });

  group('externalMarketLinks', () {
    test('includes provider, Wikipedia, Google Finance, and TradingView', () {
      final links = externalMarketLinks(
        symbol: 'AAPL',
        dataSourceId: 'yahoo',
        exchange: 'NMS',
      );
      expect(links.map((l) => l.label).toList(), [
        'View on Yahoo Finance',
        'Wikipedia',
        'Google Finance',
        'TradingView',
      ]);
      expect(
        links[0].uri.toString(),
        'https://finance.yahoo.com/quote/AAPL',
      );
      expect(
        links[1].uri.toString(),
        'https://en.wikipedia.org/wiki/Apple_Inc.',
      );
      expect(
        links[2].uri.toString(),
        'https://www.google.com/finance/quote/AAPL:NASDAQ',
      );
      expect(
        links[3].uri.toString(),
        'https://www.tradingview.com/chart/?symbol=NASDAQ%3AAAPL',
      );
    });

    test('includes Crypto.com provider for crypto pairs', () {
      final links = externalMarketLinks(
        symbol: 'BTC_USD',
        dataSourceId: 'crypto_com',
      );
      expect(links.map((l) => l.label).toList(), [
        'View on Crypto.com',
        'Wikipedia',
        'Google Finance',
        'TradingView',
      ]);
      expect(
        links[0].uri.toString(),
        'https://crypto.com/exchange/trade/BTC_USD',
      );
    });

    test('omits Wikipedia when symbol is unmapped', () {
      final links = externalMarketLinks(
        symbol: 'ZZZZ',
        dataSourceId: 'yahoo',
      );
      expect(links.map((l) => l.label).toList(), [
        'View on Yahoo Finance',
        'Google Finance',
        'TradingView',
      ]);
    });

    test('omits provider when source is unknown', () {
      final links = externalMarketLinks(symbol: 'AAPL');
      expect(links.map((l) => l.label).toList(), [
        'Wikipedia',
        'Google Finance',
        'TradingView',
      ]);
    });

    test('returns empty for blank symbol', () {
      expect(externalMarketLinks(symbol: '  '), isEmpty);
    });
  });
}
