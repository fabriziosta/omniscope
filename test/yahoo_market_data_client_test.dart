import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/market/yahoo_market_data_client.dart';

import 'support/venue_http_fixtures.dart';

void main() {
  test('chartRequestUri is direct on native and proxied on web', () {
    final client = YahooMarketDataClient();
    final native = client.chartRequestUri(
      'AAPL',
      range: '1mo',
      interval: '1d',
      forceWeb: false,
    );
    expect(native.host, 'query1.finance.yahoo.com');
    expect(native.path, contains('/v8/finance/chart/AAPL'));
    expect(native.toString(), isNot(contains('proxy.cors.dev')));

    final web = client.chartRequestUri(
      'AAPL',
      range: '1mo',
      interval: '1d',
      forceWeb: true,
    );
    expect(web.toString(), startsWith(YahooMarketDataClient.defaultWebCorsProxyPrefix));
    expect(web.toString(), contains('query1.finance.yahoo.com'));
  });

  test('getQuotes maps chart meta into Quote', () async {
    final mock = VenueHttpFixtures.mockClient({
      (r) => VenueHttpFixtures.pathContains(r, 'AAPL'): (_) {
        return VenueHttpFixtures.jsonResponse('yahoo/chart-aapl.json');
      },
    });

    final client = YahooMarketDataClient(httpClient: mock);
    final quotes = await client.getQuotes(const ['AAPL']);
    expect(quotes, hasLength(1));
    expect(quotes.single.symbol, 'AAPL');
    expect(quotes.single.price, 190.5);
    expect(quotes.single.dataSourceId, YahooMarketDataClient.meta.id);
    expect(quotes.single.change, closeTo(2.5, 1e-9));
  });

  test('getHistory maps chart indicators into Candles', () async {
    final mock = VenueHttpFixtures.mockClient({
      (r) {
        expect(r.url.queryParameters['range'], '1mo');
        expect(r.url.queryParameters['interval'], '1d');
        return VenueHttpFixtures.pathContains(r, 'AAPL');
      }: (_) => VenueHttpFixtures.jsonResponse('yahoo/chart-aapl.json'),
    });

    final client = YahooMarketDataClient(httpClient: mock);
    final candles = await client.getHistory(
      'AAPL',
      range: '1mo',
      interval: '1d',
    );
    expect(candles, hasLength(2));
    expect(candles.first.close, 188.0);
    expect(candles.last.close, 190.5);
    expect(candles.first.open, 187.0);
    expect(candles.last.volume, 200);
  });

  test('encodes special symbols in the request path', () {
    final client = YahooMarketDataClient();
    final uri = client.chartRequestUri(
      '^GSPC',
      range: '5d',
      interval: '1d',
      forceWeb: false,
    );
    expect(uri.path, contains('%5EGSPC'));
  });
}
