import '../market/models.dart';
import '../trading/order_models.dart';
import 'crypto_exchange.dart';
import 'exchange_portfolio.dart';

/// Swappable public market-data boundary for crypto exchanges.
///
/// UI never calls exchange URLs — only this interface (via registry / router).
/// Map each venue’s DTOs → [Quote] / [Candle] inside the concrete adapter.
///
/// Optional private credentials enable [canFetchPortfolio] / [fetchPortfolio]
/// for live balances on the Portfolio tab, and [canPlaceOrders] / [placeOrder]
/// for agent-confirmed live trades (Practice routes separately via TradeExecutor).
abstract class CryptoExchangeClient {
  CryptoExchange get exchange;

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
  bool get supportsLivePortfolio => false;

  /// True when private credentials are present for a live portfolio fetch.
  bool get canFetchPortfolio => false;

  /// Live account balances. Only call when [canFetchPortfolio] is true.
  Future<ExchangePortfolioSnapshot> fetchPortfolio() {
    throw UnsupportedError(
      '${exchange.displayName} does not support live portfolio',
    );
  }

  /// Whether this venue can place live orders once credentials are set.
  bool get supportsLiveTrading => false;

  /// True when private credentials are present for live order placement.
  bool get canPlaceOrders => false;

  /// Place a live order. Only call when [canPlaceOrders] is true.
  Future<OrderResult> placeOrder(OrderRequest request) {
    throw UnsupportedError(
      '${exchange.displayName} does not support live order placement',
    );
  }

  Future<OrderResult> cancelOrder(String orderId) {
    throw UnsupportedError(
      '${exchange.displayName} does not support cancel order',
    );
  }

  Future<OrderResult> getOrder(String orderId) {
    throw UnsupportedError(
      '${exchange.displayName} does not support order status',
    );
  }
}
