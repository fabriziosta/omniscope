import '../market/exchange_credentials.dart';
import 'venue_trading_mode.dart';

/// Declares which credential fields a venue needs in Settings / `.env`.
///
/// Settings renders a generic Configure dialog from this schema — venue folders
/// must not ship their own credential cards.
class VenueCredentialSchema {
  const VenueCredentialSchema({
    required this.venueId,
    required this.displayName,
    this.requiresApiKey = true,
    this.requiresApiSecret = true,
    this.requiresApiToken = false,
    this.apiTokenOptional = true,
    this.supportsTradingMode = false,
    this.defaultTradingMode = VenueTradingMode.paper,
    this.docsUrl = '',
    this.subtitleWhenPublic =
        'Not configured — public market data still works',
    this.subtitleWhenReady =
        'Configured — Live portfolio + trading ready',
    this.subtitleWhenPartial =
        'Partial — Live portfolio / trading need key and secret',
  });

  final String venueId;
  final String displayName;

  final bool requiresApiKey;
  final bool requiresApiSecret;

  /// When true, show an API token field (optional unless [apiTokenOptional] is false).
  final bool requiresApiToken;
  final bool apiTokenOptional;

  /// Paper / live mode selector (Alpaca-style dual endpoints).
  final bool supportsTradingMode;
  final VenueTradingMode defaultTradingMode;

  final String docsUrl;

  final String subtitleWhenPublic;
  final String subtitleWhenReady;
  final String subtitleWhenPartial;

  String get apiKeyEnvName =>
      ExchangeCredentialsConfig.apiKeyEnvName(venueId);

  String get apiSecretEnvName =>
      ExchangeCredentialsConfig.apiSecretEnvName(venueId);

  String get apiTokenEnvName =>
      ExchangeCredentialsConfig.apiTokenEnvName(venueId);

  String get tradingModeEnvName =>
      ExchangeCredentialsConfig.tradingModeEnvName(venueId);

  /// Status line under the credentials card.
  String subtitleFor(ExchangeCredentials creds) {
    final liveReady = isLiveReady(creds);
    if (!creds.isConfigured && !creds.hasApiSecret) {
      return subtitleWhenPublic;
    }
    if (liveReady) return subtitleWhenReady;
    return subtitleWhenPartial;
  }

  /// Whether key/secret (and token when required) unlock private APIs.
  bool isLiveReady(ExchangeCredentials creds) {
    if (requiresApiKey && !creds.hasApiKey) return false;
    if (requiresApiSecret && !creds.hasApiSecret) return false;
    if (requiresApiToken && !apiTokenOptional && !creds.hasApiToken) {
      return false;
    }
    return creds.hasApiKey || creds.hasApiToken;
  }
}
