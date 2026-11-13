import '../../market/exchange_credentials.dart';
import '../../venues/venue_trading_mode.dart';

/// Alpaca Trading API auth headers and base URL selection.
abstract final class AlpacaAuth {
  static const paperBaseUrl = 'https://paper-api.alpaca.markets';
  static const liveBaseUrl = 'https://api.alpaca.markets';

  static String baseUrlFor(ExchangeCredentials credentials) {
    return credentials.resolvedTradingMode == VenueTradingMode.live
        ? liveBaseUrl
        : paperBaseUrl;
  }

  static Map<String, String> headers(ExchangeCredentials credentials) {
    return {
      'APCA-API-KEY-ID': credentials.apiKey ?? '',
      'APCA-API-SECRET-KEY': credentials.apiSecret ?? '',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }
}
