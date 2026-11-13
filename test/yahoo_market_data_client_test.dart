import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/data/market/yahoo_market_data_client.dart';

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
    final mock = MockClient((request) async {
      expect(request.url.path, contains('AAPL'));
      return http.Response(
        jsonEncode({
          'chart': {
            'result': [
              {
                'meta': {
                  'symbol': 'AAPL',
                  'regularMarketPrice': 190.5,
                  'previousClose': 188.0,
                  'currency': 'USD',
                  'shortName': 'Apple',
                  'fullExchangeName': 'NasdaqGS',
                },
                'timestamp': [1, 2],
                'indicators': {
                  'quote': [
                    {
                      'close': [188.0, 190.5],
                      'open': [187.0, 189.0],
                      'high': [189.0, 191.0],
                      'low': [186.0, 188.0],
                      'volume': [100, 200],
                    },
                  ],
                },
              },
            ],
            'error': null,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = YahooMarketDataClient(httpClient: mock);
    final quotes = await client.getQuotes(const ['AAPL']);
    expect(quotes, hasLength(1));
    expect(quotes.single.symbol, 'AAPL');
    expect(quotes.single.price, 190.5);
    expect(quotes.single.dataSourceId, YahooMarketDataClient.meta.id);
    expect(quotes.single.change, closeTo(2.5, 1e-9));
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
