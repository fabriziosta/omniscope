import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/core/dotenv_asset.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/market/market_data_client.dart';

import 'support/venue_http_fixtures.dart';

void main() {
  test('loads Crypto.com credentials from shared .env values', () {
    const raw = '''
OMNISCOPE_CRYPTO_COM_API_KEY=cdc-key
OMNISCOPE_CRYPTO_COM_API_SECRET="cdc-secret"
OMNISCOPE_CRYPTO_COM_API_TOKEN='cdc-token'
OMNISCOPE_OPENAI_API_KEY=sk-openai
''';
    final values = DotEnvAsset.parse(raw);
    final config = ExchangeCredentialsConfig.fromValues(values);
    final creds = config.forId('crypto_com');
    expect(creds.apiKey, 'cdc-key');
    expect(creds.apiSecret, 'cdc-secret');
    expect(creds.apiToken, 'cdc-token');
    expect(creds.isConfigured, isTrue);
    expect(
      ExchangeCredentialsConfig.apiKeyEnvName('crypto_com'),
      'OMNISCOPE_CRYPTO_COM_API_KEY',
    );

    final client = CryptoComExchangeClient(credentials: creds);
    expect(client.hasCredentials, isTrue);
    expect(client.canFetchPortfolio, isTrue);
    expect(client.credentials.apiSecret, 'cdc-secret');
  });

  test('canFetchPortfolio and canPlaceOrders require api key and secret', () {
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(apiKey: 'only-key'),
      ).canFetchPortfolio,
      isFalse,
    );
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(apiKey: 'only-key'),
      ).canPlaceOrders,
      isFalse,
    );
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(apiSecret: 'only-secret'),
      ).canFetchPortfolio,
      isFalse,
    );
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      ).canFetchPortfolio,
      isTrue,
    );
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      ).canPlaceOrders,
      isTrue,
    );
    expect(
      CryptoComExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      ).supportsLiveTrading,
      isTrue,
    );
  });

  test('signs private requests with HMAC-SHA256', () {
    final sig = CryptoComExchangeClient.signRequest(
      method: 'private/user-balance',
      id: 11,
      apiKey: 'token',
      params: const {},
      nonce: 1611022832613,
      apiSecret: 'secretKey',
    );
    expect(sig, hasLength(64));
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(sig), isTrue);

    final again = CryptoComExchangeClient.signRequest(
      method: 'private/user-balance',
      id: 11,
      apiKey: 'token',
      params: const {},
      nonce: 1611022832613,
      apiSecret: 'secretKey',
    );
    expect(again, sig);

    expect(
      CryptoComExchangeClient.paramsToString({'b': '2', 'a': '1'}),
      'a1b2',
    );
  });

  test('maps Crypto.com user-balance JSON to portfolio snapshot', () {
    final envelope =
        VenueHttpFixtures.readJsonObject('crypto_com/user-balance.json');
    final result = envelope['result'] as Map<String, dynamic>;
    final data = result['data'] as List;
    final snapshot = CryptoComExchangeClient.portfolioFromUserBalance(
      data.first as Map<String, dynamic>,
      exchangeId: 'crypto_com',
      exchangeName: 'Crypto.com',
    );

    expect(snapshot.exchangeName, 'Crypto.com');
    expect(snapshot.totalValue, closeTo(7890, 0.01));
    expect(snapshot.availableValue, closeTo(4721.05, 0.01));
    expect(snapshot.currency, 'USD');
    expect(snapshot.balances, hasLength(2));
    expect(snapshot.balances.first.asset, 'CRO');
    expect(snapshot.balances.first.marketValue, closeTo(4776.10, 0.01));
    expect(snapshot.balances.last.asset, 'USD');
  });

  test('maps Crypto.com ticker JSON to Quote', () {
    final envelope =
        VenueHttpFixtures.readJsonObject('crypto_com/get-tickers.json');
    final result = envelope['result'] as Map<String, dynamic>;
    final data = result['data'] as List;
    final quote = CryptoComExchangeClient.quoteFromTicker(
      data.first as Map<String, dynamic>,
    );

    expect(quote.symbol, 'BTC_USD');
    expect(quote.name, 'BTC / USD');
    expect(quote.currency, 'USD');
    expect(quote.price, closeTo(71449.35, 0.001));
    expect(quote.changePercent, closeTo(-0.0282, 0.0001));
    expect(quote.change, isNotNull);
    expect(quote.change! < 0, isTrue);
    expect(quote.exchange, 'Crypto.com');
    expect(quote.isUp, isFalse);
  });

  test('maps Crypto.com candle JSON to Candle', () {
    final envelope =
        VenueHttpFixtures.readJsonObject('crypto_com/get-candlestick.json');
    final result = envelope['result'] as Map<String, dynamic>;
    final data = result['data'] as List;
    final candle = CryptoComExchangeClient.candleFromRow(
      data.first as Map<String, dynamic>,
    );

    expect(candle.open, 100);
    expect(candle.high, 110);
    expect(candle.low, 90);
    expect(candle.close, 105);
    expect(candle.volume, 12.5);
    expect(
      candle.time,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  test('handlesSymbol recognizes spot pairs', () {
    final client = CryptoComExchangeClient();
    expect(client.hasCredentials, isFalse);
    expect(client.canFetchPortfolio, isFalse);
    expect(client.handlesSymbol('BTC_USD'), isTrue);
    expect(client.handlesSymbol('ETH_USDT'), isTrue);
    expect(client.handlesSymbol('AAPL'), isFalse);
    expect(client.handlesSymbol('BTC-USD'), isFalse);
  });

  test('default browse catalog is larger curated USD set', () {
    expect(CryptoComExchangeClient.meta.defaultSymbols.length, greaterThan(6));
    expect(
      CryptoComExchangeClient.meta.defaultSymbols,
      containsAll(['BTC_USD', 'ETH_USD', 'SOL_USD', 'POL_USD', 'SKY_USD']),
    );
    expect(
      CryptoComExchangeClient.meta.defaultSymbols,
      isNot(contains('MATIC_USD')),
    );
    expect(
      CryptoComExchangeClient.meta.defaultSymbols,
      isNot(contains('MKR_USD')),
    );
    expect(
      CryptoComExchangeClient.meta.defaultSymbols,
      isNot(contains('TRX_USD')),
    );
  });

  test('getQuotes skips delisted instruments that return HTTP 400', () async {
    final client = CryptoComExchangeClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/public/get-tickers')) {
          final instrument = request.url.queryParameters['instrument_name'];
          if (instrument == null || instrument.isEmpty) {
            // Bulk path — omit delisted MATIC_USD.
            return http.Response(
              jsonEncode({
                'code': 0,
                'result': {
                  'data': [
                    {
                      'i': 'BTC_USD',
                      'a': '100',
                      'c': '0.01',
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (instrument == 'MATIC_USD') {
            return http.Response(
              jsonEncode({
                'code': 40004,
                'message': 'Invalid instrument_name',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          if (instrument == 'BTC_USD') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'result': {
                  'data': [
                    {'i': 'BTC_USD', 'a': '100', 'c': '0.01'},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response('unexpected ${request.url}', 500);
      }),
    );

    final quotes = await client.getQuotes(['BTC_USD', 'MATIC_USD']);
    expect(quotes.map((q) => q.symbol), ['BTC_USD']);
  });

  test('getQuotes falls back per-symbol when bulk tickers fail', () async {
    var bulkCalls = 0;
    final client = CryptoComExchangeClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/public/get-tickers')) {
          final instrument = request.url.queryParameters['instrument_name'];
          if (instrument == null || instrument.isEmpty) {
            bulkCalls += 1;
            return http.Response(
              jsonEncode({
                'code': 40004,
                'message': 'Invalid instrument_name',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          if (instrument == 'ETH_USD') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'result': {
                  'data': [
                    {'i': 'ETH_USD', 'a': '200', 'c': '-0.02'},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'code': 40004,
              'message': 'Invalid instrument_name',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected ${request.url}', 500);
      }),
    );

    final quotes = await client.getQuotes(['ETH_USD', 'MATIC_USD']);
    expect(bulkCalls, 1);
    expect(quotes.map((q) => q.symbol), ['ETH_USD']);
  });

  test('browseSymbols drops curated defaults missing from live catalog', () async {
    final client = CryptoComExchangeClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/public/get-instruments'));
        expect(request.url.hasQuery, isFalse);
        return http.Response(
          jsonEncode({
            'code': 0,
            'result': {
              'data': [
                {
                  'symbol': 'BTC_USD',
                  'inst_type': 'CCY_PAIR',
                  'quote_ccy': 'USD',
                  'tradable': true,
                },
                {
                  'symbol': 'ETH_USD',
                  'inst_type': 'CCY_PAIR',
                  'quote_ccy': 'USD',
                  'tradable': true,
                },
                {
                  'symbol': 'AAVE_USD',
                  'inst_type': 'CCY_PAIR',
                  'quote_ccy': 'USD',
                  'tradable': true,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final symbols = await client.browseSymbols();
    expect(symbols.take(3).toList(), ['BTC_USD', 'ETH_USD', 'AAVE_USD']);
    expect(symbols, isNot(contains('MATIC_USD')));
  });

  test('non-200 Crypto.com errors include body detail', () async {
    final client = CryptoComExchangeClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"code":40004,"message":"Invalid instrument_name"}',
          400,
        ),
      ),
    );
    await expectLater(
      client.getQuotes(['MATIC_USD']),
      throwsA(
        isA<MarketDataException>().having(
          (e) => e.message,
          'message',
          contains('Invalid instrument_name'),
        ),
      ),
    );
  });

  group('HTTP fixtures', () {
    test('getQuotes maps bulk get-tickers fixture', () async {
      final client = CryptoComExchangeClient(
        httpClient: VenueHttpFixtures.mockClient({
          (r) =>
              VenueHttpFixtures.isGet(r) &&
              VenueHttpFixtures.pathContains(r, '/public/get-tickers'):
              (_) => VenueHttpFixtures.jsonResponse(
                    'crypto_com/get-tickers.json',
                  ),
        }),
      );

      final quotes = await client.getQuotes(const ['BTC_USD', 'ETH_USD']);
      expect(quotes, hasLength(2));
      expect(quotes.map((q) => q.symbol), containsAll(['BTC_USD', 'ETH_USD']));
      expect(
        quotes.firstWhere((q) => q.symbol == 'BTC_USD').price,
        closeTo(71449.35, 0.001),
      );
    });

    test('getHistory maps get-candlestick fixture', () async {
      final client = CryptoComExchangeClient(
        httpClient: VenueHttpFixtures.mockClient({
          (r) =>
              VenueHttpFixtures.isGet(r) &&
              VenueHttpFixtures.pathContains(r, '/public/get-candlestick'):
              (r) {
            expect(r.url.queryParameters['instrument_name'], 'BTC_USD');
            return VenueHttpFixtures.jsonResponse(
              'crypto_com/get-candlestick.json',
            );
          },
        }),
      );

      final candles = await client.getHistory(
        'BTC_USD',
        range: '1mo',
        interval: '1d',
      );
      expect(candles, hasLength(2));
      expect(candles.first.close, 105);
      expect(candles.last.close, 118);
    });

    test('browseSymbols filters USD spot from get-instruments fixture',
        () async {
      final client = CryptoComExchangeClient(
        httpClient: VenueHttpFixtures.mockClient({
          (r) =>
              VenueHttpFixtures.isGet(r) &&
              VenueHttpFixtures.pathContains(r, '/public/get-instruments'):
              (_) => VenueHttpFixtures.jsonResponse(
                    'crypto_com/get-instruments.json',
                  ),
        }),
      );

      final symbols = await client.browseSymbols();
      expect(symbols, containsAll(['BTC_USD', 'ETH_USD']));
      expect(symbols, isNot(contains('ETH_USDT')));
      expect(symbols, isNot(contains('SOL_USD'))); // tradable: false
      expect(symbols, isNot(contains('BTCUSD-PERP')));
      expect(symbols.first, 'BTC_USD');
    });

    test('fetchPortfolio posts private user-balance fixture', () async {
      http.BaseRequest? seen;
      final client = CryptoComExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        httpClient: VenueHttpFixtures.mockClient({
          (r) =>
              VenueHttpFixtures.isPost(r) &&
              VenueHttpFixtures.pathContains(r, 'private/user-balance'): (r) {
            seen = r;
            return VenueHttpFixtures.jsonResponse(
              'crypto_com/user-balance.json',
            );
          },
        }),
      );

      final snapshot = await client.fetchPortfolio();
      expect(seen, isNotNull);
      expect(snapshot.totalValue, closeTo(7890, 0.01));
      expect(snapshot.balances.first.asset, 'CRO');
    });
  });
}
