import '../crypto/crypto_exchange_client.dart';
import '../market/exchange_credentials.dart';
import '../trading/broker_exchange_client.dart';
import 'live_venue_capabilities.dart';
import 'venue_credential_schema.dart';
import 'venue_kind.dart';

/// One registered venue adapter + optional Settings credential schema.
class VenueRegistration {
  const VenueRegistration._({
    required this.kind,
    required this.id,
    required this.displayName,
    required this.schema,
    required this.live,
    this.cryptoClient,
    this.brokerClient,
  });

  factory VenueRegistration.crypto({
    required CryptoExchangeClient client,
    required VenueCredentialSchema schema,
  }) {
    final live = client as LiveVenueCapabilities;
    return VenueRegistration._(
      kind: VenueKind.crypto,
      id: client.exchange.id,
      displayName: client.exchange.displayName,
      schema: schema,
      live: live,
      cryptoClient: client,
    );
  }

  factory VenueRegistration.broker({
    required BrokerExchangeClient client,
    required VenueCredentialSchema schema,
  }) {
    final live = client as LiveVenueCapabilities;
    return VenueRegistration._(
      kind: VenueKind.broker,
      id: client.broker.id,
      displayName: client.broker.displayName,
      schema: schema,
      live: live,
      brokerClient: client,
    );
  }

  final VenueKind kind;
  final String id;
  final String displayName;
  final VenueCredentialSchema schema;
  final LiveVenueCapabilities live;
  final CryptoExchangeClient? cryptoClient;
  final BrokerExchangeClient? brokerClient;

  void applyCredentials(ExchangeCredentials credentials) {
    live.setCredentials(credentials);
  }
}
