import '../market/exchange_credentials.dart';
import '../market/models.dart';
import '../trading/order_models.dart';
import '../venues/exchange_portfolio.dart';
import '../venues/live_venue_capabilities.dart';
import 'crypto_exchange.dart';

/// Swappable public market-data boundary for crypto exchanges.
///
/// UI never calls exchange URLs — only this interface (via registry / router).
/// Map each venue’s DTOs → [Quote] / [Candle] inside the concrete adapter.
///
/// Optional private credentials enable [canFetchPortfolio] / [fetchPortfolio]
/// for live balances on the Portfolio tab, and [canPlaceOrders] / [placeOrder]
/// for agent-confirmed live trades (Practice routes separately via TradeExecutor).
abstract class CryptoExchangeClient implements LiveVenueCapabilities {
  CryptoExchange get exchange;

  @override
  String get venueId => exchange.id;

  @override
  String get displayName => exchange.displayName;

  @override
  ExchangeCredentials get credentials => ExchangeCredentials.empty;

  @override
  void setCredentials(ExchangeCredentials value) {}

  /// Whether this adapter should serve [symbol] (routing + portfolio marks).
  bool handlesSymbol(String symbol);

  Future<List<Quote>> getQuotes(List<String> symbols);

  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  });

  /// Symbols to browse on the Crypto exchange screen (paginated quotes).
  ///
  /// Default: [CryptoExchange.defaultSymbols]. Venues may discover a larger
  /// public catalog (e.g. Crypto.com `get-instruments`) and fall back to the
  /// curated defaults on failure.
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  /// Whether this venue can expose a Live portfolio once credentials are set.
  @override
  bool get supportsLivePortfolio => false;

  /// True when private credentials are present for a live portfolio fetch.
  @override
  bool get canFetchPortfolio => false;

  /// Live account balances. Only call when [canFetchPortfolio] is true.
  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() {
    throw UnsupportedError(
      '${exchange.displayName} does not support live portfolio',
    );
  }

  /// Whether this venue can place live orders once credentials are set.
  @override
  bool get supportsLiveTrading => false;

  /// True when private credentials are present for live order placement.
  @override
  bool get canPlaceOrders => false;

  /// Place a live order. Only call when [canPlaceOrders] is true.
  @override
  Future<OrderResult> placeOrder(OrderRequest request) {
    throw UnsupportedError(
      '${exchange.displayName} does not support live order placement',
    );
  }

  @override
  Future<OrderResult> cancelOrder(String orderId) {
    throw UnsupportedError(
      '${exchange.displayName} does not support cancel order',
    );
  }

  @override
  Future<OrderResult> getOrder(String orderId) {
    throw UnsupportedError(
      '${exchange.displayName} does not support order status',
    );
  }
}
