import 'crypto_exchange_client.dart';

/// Registered crypto venues for the Crypto group UI and symbol routing.
class CryptoExchangeRegistry {
  const CryptoExchangeRegistry(this.exchanges);

  /// Full catalog (Settings lists these; UI routing may filter further).
  final List<CryptoExchangeClient> exchanges;

  CryptoExchangeClient? clientForId(String id) {
    for (final client in exchanges) {
      if (client.exchange.id == id) return client;
    }
    return null;
  }

  CryptoExchangeClient? clientForSymbol(String symbol) {
    for (final client in exchanges) {
      if (client.handlesSymbol(symbol)) return client;
    }
    return null;
  }

  bool handlesSymbol(String symbol) => clientForSymbol(symbol) != null;

  /// Catalog filtered by [isEnabled] (typically Settings → crypto toggles).
  List<CryptoExchangeClient> enabledWhere(bool Function(String id) isEnabled) {
    return [
      for (final client in exchanges)
        if (isEnabled(client.exchange.id)) client,
    ];
  }

  /// Venues that can show Live balances once API credentials are added.
  List<CryptoExchangeClient> get livePortfolioCapableClients => [
        for (final client in exchanges)
          if (client.supportsLivePortfolio) client,
      ];

  /// Live-capable venues that still need credentials (Portfolio connect CTA).
  List<CryptoExchangeClient> get pendingLivePortfolioClients => [
        for (final client in livePortfolioCapableClients)
          if (!client.canFetchPortfolio) client,
      ];

  /// Venues with private credentials ready for Portfolio → Live subgroups.
  List<CryptoExchangeClient> get portfolioClients => [
        for (final client in exchanges)
          if (client.canFetchPortfolio) client,
      ];

  /// [portfolioClients] limited to venues still enabled in Settings.
  List<CryptoExchangeClient> portfolioClientsWhere(
    bool Function(String id) isEnabled,
  ) {
    return [
      for (final client in portfolioClients)
        if (isEnabled(client.exchange.id)) client,
    ];
  }

  /// Venues with credentials ready for live order placement.
  List<CryptoExchangeClient> get tradableClients => [
        for (final client in exchanges)
          if (client.canPlaceOrders) client,
      ];

  /// [tradableClients] limited to venues still enabled in Settings.
  List<CryptoExchangeClient> tradableClientsWhere(
    bool Function(String id) isEnabled,
  ) {
    return [
      for (final client in tradableClients)
        if (isEnabled(client.exchange.id)) client,
    ];
  }
}
