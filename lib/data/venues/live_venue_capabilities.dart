import '../market/exchange_credentials.dart';
import '../trading/order_models.dart';
import 'exchange_portfolio.dart';

/// Shared private-API surface for crypto venues and equity brokers.
///
/// Public market data stays on [MarketDataClient] / crypto public methods.
/// Settings, Portfolio Live, and [TradeExecutor] gate on these flags.
abstract interface class LiveVenueCapabilities {
  String get venueId;

  String get displayName;

  ExchangeCredentials get credentials;

  void setCredentials(ExchangeCredentials value);

  bool get supportsLivePortfolio;

  bool get canFetchPortfolio;

  Future<ExchangePortfolioSnapshot> fetchPortfolio();

  bool get supportsLiveTrading;

  bool get canPlaceOrders;

  Future<OrderResult> placeOrder(OrderRequest request);

  Future<OrderResult> cancelOrder(String orderId);

  Future<OrderResult> getOrder(String orderId);
}
