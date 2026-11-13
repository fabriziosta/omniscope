import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/dotenv_asset.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';

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
    final snapshot = CryptoComExchangeClient.portfolioFromUserBalance(
      {
        'total_available_balance': '4721.05',
        'total_cash_balance': '7890.00',
        'instrument_name': 'USD',
        'position_balances': [
          {
            'instrument_name': 'CRO',
            'quantity': '24422.72',
            'market_value': '4776.10',
            'max_withdrawal_balance': '24422.72',
            'reserved_qty': '0',
          },
          {
            'instrument_name': 'USD',
            'quantity': '3113.50',
            'market_value': '3113.50',
            'max_withdrawal_balance': '3113.50',
            'reserved_qty': '0',
          },
          {
            'instrument_name': 'DUST',
            'quantity': '0',
            'market_value': '0',
          },
        ],
      },
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
    final quote = CryptoComExchangeClient.quoteFromTicker({
      'i': 'BTC_USD',
      'a': '71449.35',
      'c': '-0.0282',
    });

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
    final candle = CryptoComExchangeClient.candleFromRow({
      'o': '100',
      'h': '110',
      'l': '90',
      'c': '105',
      'v': '12.5',
      't': 1700000000000,
    });

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
      containsAll(['BTC_USD', 'ETH_USD', 'SOL_USD']),
    );
  });
}
