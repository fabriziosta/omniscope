import '../crypto/crypto_exchange_client.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../settings/data_source_settings.dart';
import 'broker_exchange_client.dart';
import 'broker_exchange_registry.dart';
import 'order_models.dart';

/// Live order submission boundary. Never routes to paper portfolio.
abstract class TradeExecutor {
  /// True when at least one enabled venue can place orders.
  bool get canTrade;

  /// Enabled venues that can place orders right now.
  List<TradableVenue> get tradableVenues;

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
}

enum TradableVenueKind {
  crypto,
  broker,
}

/// Routes [OrderRequest]s to crypto or broker adapters that can place orders.
class RoutingTradeExecutor implements TradeExecutor {
  RoutingTradeExecutor({
    required this.cryptoRegistry,
    required this.brokerRegistry,
    required this.dataSources,
  });

  final CryptoExchangeRegistry cryptoRegistry;
  final BrokerExchangeRegistry brokerRegistry;
  final DataSourceSettings dataSources;

  bool _cryptoEnabled(String id) => dataSources.isCryptoEnabled(id);

  bool _brokerEnabled(String id) => dataSources.isBrokerEnabled(id);

  @override
  bool get canTrade => tradableVenues.isNotEmpty;

  @override
  List<TradableVenue> get tradableVenues {
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

  @override
  Future<OrderResult> submit(OrderRequest request) async {
    final exchangeId = request.exchangeId.trim();
    if (exchangeId.isEmpty) {
      return const OrderResult.fail('Exchange is required.');
    }
    if (request.quantity <= 0) {
      return const OrderResult.fail('Quantity must be greater than zero.');
    }
    if (request.symbol.trim().isEmpty) {
      return const OrderResult.fail('Symbol is required.');
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
      'No connected exchange can trade for "$exchangeId". '
      'Configure credentials under Settings → Data sources.',
    );
  }
}
