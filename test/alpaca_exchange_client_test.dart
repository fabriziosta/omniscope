import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/brokers/alpaca/alpaca_auth.dart';
import 'package:omniscope/data/brokers/alpaca/alpaca_dto.dart';
import 'package:omniscope/data/brokers/alpaca/alpaca_exchange_client.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/trading/order_models.dart';
import 'package:omniscope/data/venues/venue_trading_mode.dart';

import 'support/venue_http_fixtures.dart';

void main() {
  group('AlpacaAuth', () {
    test('defaults to paper base URL', () {
      expect(
        AlpacaAuth.baseUrlFor(ExchangeCredentials.empty),
        AlpacaAuth.paperBaseUrl,
      );
    });

    test('uses live base URL when mode is live', () {
      expect(
        AlpacaAuth.baseUrlFor(
          const ExchangeCredentials(tradingMode: VenueTradingMode.live),
        ),
        AlpacaAuth.liveBaseUrl,
      );
    });
  });

  group('AlpacaDto', () {
    test('maps account and positions into portfolio snapshot', () {
      final snapshot = AlpacaDto.portfolioFromAccountAndPositions(
        exchangeId: 'alpaca',
        exchangeName: 'Alpaca',
        account: {
          'currency': 'USD',
          'equity': '10500.25',
          'cash': '500.25',
          'buying_power': '2000',
        },
        positions: [
          {
            'symbol': 'AAPL',
            'qty': '10',
            'qty_available': '10',
            'market_value': '1800',
          },
        ],
      );

      expect(snapshot.exchangeId, 'alpaca');
      expect(snapshot.totalValue, 10500.25);
      expect(snapshot.availableValue, 2000);
      expect(snapshot.balances.length, 2);
      expect(snapshot.balances.first.asset, 'USD');
      expect(snapshot.balances.last.asset, 'AAPL');
      expect(snapshot.balances.last.quantity, 10);
    });

    test('builds place-order body', () {
      final body = AlpacaDto.placeOrderBody(
        const OrderRequest(
          exchangeId: 'alpaca',
          symbol: 'aapl',
          side: OrderSide.buy,
          quantity: 3,
        ),
      );
      expect(body['symbol'], 'AAPL');
      expect(body['qty'], '3');
      expect(body['side'], 'buy');
      expect(body['type'], 'market');
    });
  });

  group('AlpacaExchangeClient gates', () {
    test('private APIs stay off without credentials', () {
      final client = AlpacaExchangeClient();
      expect(client.canFetchPortfolio, isFalse);
      expect(client.canPlaceOrders, isFalse);
      expect(client.supportsLivePortfolio, isTrue);
      expect(client.supportsLiveTrading, isTrue);
    });

    test('key + secret unlock portfolio and orders', () {
      final client = AlpacaExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      );
      expect(client.canFetchPortfolio, isTrue);
      expect(client.canPlaceOrders, isTrue);
    });

    test('fetchPortfolio maps HTTP fixtures', () async {
      final client = AlpacaExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
          tradingMode: VenueTradingMode.paper,
        ),
        httpClient: VenueHttpFixtures.mockClient({
          (r) => VenueHttpFixtures.pathEndsWith(r, '/v2/account'): (r) {
            expect(r.url.host, 'paper-api.alpaca.markets');
            return VenueHttpFixtures.jsonResponse('alpaca/account.json');
          },
          (r) => VenueHttpFixtures.pathEndsWith(r, '/v2/positions'): (_) =>
              VenueHttpFixtures.jsonResponse('alpaca/positions.json'),
        }),
      );

      final snapshot = await client.fetchPortfolio();
      expect(snapshot.totalValue, 1000);
      expect(snapshot.balances.single.asset, 'USD');
    });

    test('placeOrder posts to paper host when configured', () async {
      final client = AlpacaExchangeClient(
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
        httpClient: VenueHttpFixtures.mockClient({
          (r) =>
              VenueHttpFixtures.isPost(r) &&
              VenueHttpFixtures.pathEndsWith(r, '/v2/orders'): (r) {
            expect(r.method, 'POST');
            return VenueHttpFixtures.jsonResponse('alpaca/place-order.json');
          },
        }),
      );

      final result = await client.placeOrder(
        const OrderRequest(
          exchangeId: 'alpaca',
          symbol: 'AAPL',
          side: OrderSide.buy,
          quantity: 1,
        ),
      );
      expect(result.success, isTrue);
      expect(result.orderId, 'ord-1');
    });
  });
}
