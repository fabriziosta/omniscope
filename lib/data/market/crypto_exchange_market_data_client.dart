import '../crypto/crypto_exchange_client.dart';
import 'market_data_client.dart';
import 'models.dart';

/// Adapts a [CryptoExchangeClient] to the shared [MarketDataClient] boundary.
class CryptoExchangeMarketDataClient implements MarketDataClient {
  CryptoExchangeMarketDataClient(this._crypto);

  final CryptoExchangeClient _crypto;

  CryptoExchangeClient get cryptoClient => _crypto;

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) =>
      _crypto.getQuotes(symbols);

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) {
    return _crypto.getHistory(
      symbol,
      range: range,
      interval: interval,
    );
  }
}
