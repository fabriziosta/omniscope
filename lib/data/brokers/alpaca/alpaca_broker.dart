import '../../trading/broker_exchange.dart';
import '../../venues/venue_credential_schema.dart';
import '../../venues/venue_trading_mode.dart';

/// Alpaca brokerage metadata and Settings credential schema.
abstract final class AlpacaBroker {
  static const BrokerExchange meta = BrokerExchange(
    id: 'alpaca',
    displayName: 'Alpaca',
    description: 'US stocks and ETFs via paper or live API keys',
  );

  static const VenueCredentialSchema credentialSchema = VenueCredentialSchema(
    venueId: 'alpaca',
    displayName: 'Alpaca',
    requiresApiKey: true,
    requiresApiSecret: true,
    requiresApiToken: false,
    supportsTradingMode: true,
    defaultTradingMode: VenueTradingMode.paper,
    docsUrl: 'https://docs.alpaca.markets/',
    subtitleWhenPublic:
        'Not configured — add paper or live API keys to unlock',
    subtitleWhenReady: 'Configured — Live portfolio + trading ready',
    subtitleWhenPartial:
        'Partial — Live portfolio / trading need key and secret',
  );
}
