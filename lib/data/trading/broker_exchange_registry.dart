import 'broker_exchange_client.dart';

/// Registered traditional / equity broker adapters for live trading.
class BrokerExchangeRegistry {
  const BrokerExchangeRegistry(this.brokers);

  final List<BrokerExchangeClient> brokers;

  static const empty = BrokerExchangeRegistry([]);

  BrokerExchangeClient? clientForId(String id) {
    for (final client in brokers) {
      if (client.broker.id == id) return client;
    }
    return null;
  }

  List<BrokerExchangeClient> enabledWhere(bool Function(String id) isEnabled) {
    return [
      for (final client in brokers)
        if (isEnabled(client.broker.id)) client,
    ];
  }

  /// Venues that can show Live balances once API credentials are added.
  List<BrokerExchangeClient> get livePortfolioCapableClients => [
        for (final client in brokers)
          if (client.supportsLivePortfolio) client,
      ];

  /// Live-capable venues that still need credentials.
  List<BrokerExchangeClient> get pendingLivePortfolioClients => [
        for (final client in livePortfolioCapableClients)
          if (!client.canFetchPortfolio) client,
      ];

  /// Venues with private credentials ready for Portfolio → Live subgroups.
  List<BrokerExchangeClient> get portfolioClients => [
        for (final client in brokers)
          if (client.canFetchPortfolio) client,
      ];

  List<BrokerExchangeClient> portfolioClientsWhere(
    bool Function(String id) isEnabled,
  ) {
    return [
      for (final client in portfolioClients)
        if (isEnabled(client.broker.id)) client,
    ];
  }

  List<BrokerExchangeClient> get tradableClients => [
        for (final client in brokers)
          if (client.canPlaceOrders) client,
      ];

  List<BrokerExchangeClient> tradableClientsWhere(
    bool Function(String id) isEnabled,
  ) {
    return [
      for (final client in tradableClients)
        if (isEnabled(client.broker.id)) client,
    ];
  }
}
