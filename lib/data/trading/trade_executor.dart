import '../crypto/crypto_exchange_client.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../market/market_data_client.dart';
import '../portfolio/portfolio_catalog.dart';
import '../portfolio/portfolio_repository.dart';
import '../settings/data_source_settings.dart';
import 'broker_exchange_client.dart';
import 'broker_exchange_registry.dart';
import 'order_models.dart';

/// Order submission boundary for Practice paper and live venues.
abstract class TradeExecutor {
  /// True when at least one target can accept orders (Practice is always one).
  bool get canTrade;

  /// Practice first, then enabled live venues that can place orders.
  List<TradableVenue> get tradableVenues;

  /// Live venues only (excludes Practice).
  List<TradableVenue> get liveVenues;

  TradableVenue? venueForId(String exchangeId);

  Future<OrderResult> submit(OrderRequest request);
}

class TradableVenue {
  const TradableVenue({
    required this.id,
    required this.displayName,
    required this.kind,
  });

  final String id;
  final String displayName;
  final TradableVenueKind kind;

  bool get isPractice => kind == TradableVenueKind.practice;
}

enum TradableVenueKind {
  practice,
  crypto,
  broker,
}

/// Routes [OrderRequest]s to Practice paper or crypto/broker adapters.
class RoutingTradeExecutor implements TradeExecutor {
  RoutingTradeExecutor({
    required this.cryptoRegistry,
    required this.brokerRegistry,
    required this.dataSources,
    required this.portfolio,
    required this.marketData,
  });

  final CryptoExchangeRegistry cryptoRegistry;
  final BrokerExchangeRegistry brokerRegistry;
  final DataSourceSettings dataSources;
  final PortfolioRepository portfolio;
  final MarketDataClient marketData;

  static const TradableVenue practiceVenue = TradableVenue(
    id: PortfolioDescriptor.practiceId,
    displayName: 'Practice',
    kind: TradableVenueKind.practice,
  );

  bool _cryptoEnabled(String id) => dataSources.isCryptoEnabled(id);

  bool _brokerEnabled(String id) => dataSources.isBrokerEnabled(id);

  @override
  bool get canTrade => tradableVenues.isNotEmpty;

  @override
  List<TradableVenue> get liveVenues {
    final venues = <TradableVenue>[];
    for (final client in cryptoRegistry.tradableClientsWhere(_cryptoEnabled)) {
      venues.add(
        TradableVenue(
          id: client.exchange.id,
          displayName: client.exchange.displayName,
          kind: TradableVenueKind.crypto,
        ),
      );
    }
    for (final client in brokerRegistry.tradableClientsWhere(_brokerEnabled)) {
      venues.add(
        TradableVenue(
          id: client.broker.id,
          displayName: client.broker.displayName,
          kind: TradableVenueKind.broker,
        ),
      );
    }
    return venues;
  }

  @override
  List<TradableVenue> get tradableVenues => [practiceVenue, ...liveVenues];

  @override
  TradableVenue? venueForId(String exchangeId) {
    for (final v in tradableVenues) {
      if (v.id == exchangeId) return v;
    }
    return null;
  }

  CryptoExchangeClient? _cryptoClient(String id) {
    final client = cryptoRegistry.clientForId(id);
    if (client == null || !client.canPlaceOrders) return null;
    if (!_cryptoEnabled(id)) return null;
    return client;
  }

  BrokerExchangeClient? _brokerClient(String id) {
    final client = brokerRegistry.clientForId(id);
    if (client == null || !client.canPlaceOrders) return null;
    if (!_brokerEnabled(id)) return null;
    return client;
  }

  Future<OrderResult> _submitPaper(OrderRequest request) async {
    final symbol = request.symbol.trim().toUpperCase();
    try {
      final quotes = await marketData.getQuotes([symbol]);
      if (quotes.isEmpty || quotes.first.price <= 0) {
        return OrderResult.fail('No usable quote for $symbol.');
      }
      final price = quotes.first.price;
      final result = switch (request.side) {
        OrderSide.buy => await portfolio.buy(
            symbol: symbol,
            shares: request.quantity,
            price: price,
          ),
        OrderSide.sell => await portfolio.sell(
            symbol: symbol,
            shares: request.quantity,
            price: price,
          ),
      };
      if (!result.success) {
        return OrderResult.fail(result.error ?? 'Practice trade failed.');
      }
      final oid = request.clientOrderId?.trim();
      return OrderResult.ok(
        orderId: (oid != null && oid.isNotEmpty) ? 'paper-$oid' : 'paper',
        rawStatus: 'FILLED',
        message: 'Practice ${request.side.label.toLowerCase()} filled '
            'at $price',
      );
    } catch (e) {
      return OrderResult.fail('$e');
    }
  }

  @override
  Future<OrderResult> submit(OrderRequest request) async {
    final exchangeId = request.exchangeId.trim();
    if (exchangeId.isEmpty) {
      return const OrderResult.fail('Portfolio is required.');
    }
    if (request.quantity <= 0) {
      return const OrderResult.fail('Quantity must be greater than zero.');
    }
    if (request.symbol.trim().isEmpty) {
      return const OrderResult.fail('Symbol is required.');
    }

    if (exchangeId == PortfolioDescriptor.practiceId) {
      return _submitPaper(request);
    }

    final crypto = _cryptoClient(exchangeId);
    if (crypto != null) {
      try {
        return await crypto.placeOrder(request);
      } catch (e) {
        return OrderResult.fail('$e');
      }
    }

    final broker = _brokerClient(exchangeId);
    if (broker != null) {
      try {
        return await broker.placeOrder(request);
      } catch (e) {
        return OrderResult.fail('$e');
      }
    }

    return OrderResult.fail(
      'No connected portfolio can trade for "$exchangeId". '
      'Choose Practice or configure credentials under Settings → Data sources.',
    );
  }
}
