import 'package:http/http.dart' as http;

import '../brokers/alpaca/alpaca_exchange_client.dart';
import '../crypto/crypto_com/crypto_com_exchange_client.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../market/exchange_credentials.dart';
import '../trading/broker_exchange_registry.dart';
import 'venue_credential_schema.dart';
import 'venue_registration.dart';

/// Single registration list for crypto venues and equity brokers.
///
/// **Add a venue:** implement a folder under `lib/data/crypto/` or
/// `lib/data/brokers/`, then append one [VenueRegistration] in [build].
/// **Remove a venue:** delete the folder and remove that line.
///
/// Settings credentials UI, `.env` dual-sync ids, and live client fan-out all
/// derive from this catalog — do not hard-code venue ids in Settings.
class VenueCatalog {
  VenueCatalog._({
    required this.registrations,
    required this.cryptoRegistry,
    required this.brokerRegistry,
  });

  /// Empty catalog for tests that do not register live venues.
  factory VenueCatalog.empty({
    CryptoExchangeRegistry cryptoRegistry = const CryptoExchangeRegistry([]),
    BrokerExchangeRegistry brokerRegistry = BrokerExchangeRegistry.empty,
  }) {
    return VenueCatalog._(
      registrations: const [],
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
    );
  }

  final List<VenueRegistration> registrations;
  final CryptoExchangeRegistry cryptoRegistry;
  final BrokerExchangeRegistry brokerRegistry;

  /// Credential schemas for Settings (order = card order).
  List<VenueCredentialSchema> get credentialSchemas => [
        for (final r in registrations) r.schema,
      ];

  /// Venue ids that participate in secrets / `.env` dual-sync.
  List<String> get credentialVenueIds => [
        for (final r in registrations) r.id,
      ];

  /// Static ids for early bootstrap (before [build] runs).
  ///
  /// Keep in sync with the registrations constructed in [build].
  static const List<String> knownCredentialVenueIds = [
    'crypto_com',
    'alpaca',
  ];

  /// Apply Settings / `.env` credential updates to the matching live client.
  void applyCredentials(String exchangeId, ExchangeCredentials credentials) {
    for (final registration in registrations) {
      if (registration.id == exchangeId) {
        registration.applyCredentials(credentials);
        return;
      }
    }
  }

  /// Build registries from the modular venue folders.
  static VenueCatalog build({
    required ExchangeCredentials Function(String id) credentialsFor,
    http.Client? httpClient,
  }) {
    final cryptoCom = CryptoComExchangeClient(
      httpClient: httpClient,
      credentials: credentialsFor(CryptoComExchangeClient.meta.id),
    );
    final alpaca = AlpacaExchangeClient(
      httpClient: httpClient,
      credentials: credentialsFor(AlpacaExchangeClient.meta.id),
    );

    final registrations = [
      VenueRegistration.crypto(
        client: cryptoCom,
        schema: CryptoComExchangeClient.credentialSchema,
      ),
      VenueRegistration.broker(
        client: alpaca,
        schema: AlpacaExchangeClient.credentialSchema,
      ),
    ];

    ExchangeCredentialsConfig.defaultExchangeIds =
        List<String>.unmodifiable([
      for (final r in registrations) r.id,
    ]);

    return VenueCatalog._(
      registrations: registrations,
      cryptoRegistry: CryptoExchangeRegistry([cryptoCom]),
      brokerRegistry: BrokerExchangeRegistry([alpaca]),
    );
  }
}
