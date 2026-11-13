import 'models.dart';

/// Swappable market-data boundary. UI and portfolio code depend on this
/// interface only — never on a concrete provider (Yahoo, Finnhub, etc.).
abstract class MarketDataClient {
  Future<List<Quote>> getQuotes(List<String> symbols);

  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  });
}

class MarketDataException implements Exception {
  MarketDataException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'MarketDataException($statusCode): $message';
}
