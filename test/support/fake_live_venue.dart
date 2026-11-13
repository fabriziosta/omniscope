import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';

/// Shared LiveVenueCapabilities stubs for test doubles that `implements`
/// [CryptoExchangeClient].
mixin FakeCryptoLiveVenue {
  CryptoExchange get exchange;

  String get venueId => exchange.id;

  String get displayName => exchange.displayName;

  ExchangeCredentials get credentials => ExchangeCredentials.empty;

  void setCredentials(ExchangeCredentials value) {}
}
