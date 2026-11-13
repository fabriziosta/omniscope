import '../market/exchange_credentials.dart';
import '../venues/exchange_portfolio.dart';
import '../venues/live_venue_capabilities.dart';
import 'broker_exchange.dart';
import 'order_models.dart';

/// Live order + optional portfolio boundary for traditional / equity brokers.
///
/// Market data stays on [MarketDataClient]; this interface covers private APIs
/// (place / cancel / status / balances). Register adapters in
/// [BrokerExchangeRegistry] via [VenueCatalog].
abstract class BrokerExchangeClient implements LiveVenueCapabilities {
  BrokerExchange get broker;

  @override
  String get venueId => broker.id;

  @override
  String get displayName => broker.displayName;

  @override
  ExchangeCredentials get credentials => ExchangeCredentials.empty;

  @override
  void setCredentials(ExchangeCredentials value) {}

  /// Whether this broker can expose Live portfolio once credentials exist.
  @override
  bool get supportsLivePortfolio => false;

  @override
  bool get canFetchPortfolio => false;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() {
    throw UnsupportedError(
      '${broker.displayName} does not support live portfolio',
    );
  }

  /// Whether credentials are ready to place orders.
  @override
  bool get canPlaceOrders => false;

  /// Whether this broker should appear once credentials exist.
  @override
  bool get supportsLiveTrading => false;

  @override
  Future<OrderResult> placeOrder(OrderRequest request) {
    throw UnsupportedError(
      '${broker.displayName} does not support live order placement',
    );
  }

  @override
  Future<OrderResult> cancelOrder(String orderId) {
    throw UnsupportedError(
      '${broker.displayName} does not support cancel order',
    );
  }

  @override
  Future<OrderResult> getOrder(String orderId) {
    throw UnsupportedError(
      '${broker.displayName} does not support order status',
    );
  }
}
