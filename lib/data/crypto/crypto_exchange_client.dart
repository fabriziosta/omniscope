import '../market/models.dart';
import 'crypto_exchange.dart';
import 'exchange_portfolio.dart';

/// Swappable public market-data boundary for crypto exchanges.
///
/// UI never calls exchange URLs — only this interface (via registry / router).
/// Map each venue’s DTOs → [Quote] / [Candle] inside the concrete adapter.
///
/// Optional private credentials enable [canFetchPortfolio] / [fetchPortfolio]
/// for live balances on the Portfolio tab.
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
}
