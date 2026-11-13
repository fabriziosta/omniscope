import 'package:flutter/services.dart';

import '../../core/dotenv_asset.dart';
import '../venues/venue_trading_mode.dart';

/// API credentials for a market data venue, crypto exchange, or broker.
///
/// Sourced from env secrets (`.env` bootstrap + Settings UI). Public market
/// endpoints (Yahoo, Crypto.com public REST) work without these; keys enable
/// authenticated / private APIs when a client supports them.
class ExchangeCredentials {
  const ExchangeCredentials({
    this.apiKey,
    this.apiSecret,
    this.apiToken,
    this.tradingMode,
  });

  final String? apiKey;
  final String? apiSecret;

  /// Bearer / access token for venues that use token auth instead of key+secret.
  final String? apiToken;

  /// Paper vs live endpoint mode when the venue supports dual environments.
  final VenueTradingMode? tradingMode;

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;
  bool get hasApiSecret => apiSecret != null && apiSecret!.isNotEmpty;
  bool get hasApiToken => apiToken != null && apiToken!.isNotEmpty;

  /// True when at least one usable credential field is set.
  bool get isConfigured => hasApiKey || hasApiToken;

  /// Resolved trading mode (defaults to paper when unset).
  VenueTradingMode get resolvedTradingMode =>
      tradingMode ?? VenueTradingMode.paper;

  static const empty = ExchangeCredentials();

  ExchangeCredentials copyWith({
    String? apiKey,
    String? apiSecret,
    String? apiToken,
    VenueTradingMode? tradingMode,
    bool clearApiKey = false,
    bool clearApiSecret = false,
    bool clearApiToken = false,
    bool clearTradingMode = false,
  }) {
    return ExchangeCredentials(
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      apiSecret: clearApiSecret ? null : (apiSecret ?? this.apiSecret),
      apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
      tradingMode:
          clearTradingMode ? null : (tradingMode ?? this.tradingMode),
    );
  }
}

/// Exchange/market credentials keyed by venue id.
///
/// Env names follow `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` and
/// optional `OMNISCOPE_<EXCHANGE_ID>_TRADING_MODE` (`paper` / `live`).
/// `EXCHANGE_ID` is the venue id uppercased (`crypto_com` → `CRYPTO_COM`).
///
/// [defaultExchangeIds] is seeded for bootstrap; prefer
/// [VenueCatalog.credentialVenueIds] once the catalog is wired.
class ExchangeCredentialsConfig {
  ExchangeCredentialsConfig(this._byExchangeId);

  ExchangeCredentialsConfig.empty() : _byExchangeId = const {};

  /// Fallback venue ids when the catalog is unavailable (tests / early load).
  static List<String> defaultExchangeIds = const ['crypto_com', 'alpaca'];

  final Map<String, ExchangeCredentials> _byExchangeId;

  /// Credentials for an exchange id (e.g. `crypto_com`), or [ExchangeCredentials.empty].
  ExchangeCredentials forId(String exchangeId) =>
      _byExchangeId[exchangeId] ?? ExchangeCredentials.empty;

  bool get isEmpty => _byExchangeId.isEmpty;

  /// Env prefix for an exchange id: `crypto_com` → `OMNISCOPE_CRYPTO_COM`.
  static String envPrefixFor(String exchangeId) {
    final suffix = exchangeId.trim().toUpperCase().replaceAll('-', '_');
    return 'OMNISCOPE_$suffix';
  }

  static String apiKeyEnvName(String exchangeId) =>
      '${envPrefixFor(exchangeId)}_API_KEY';

  static String apiSecretEnvName(String exchangeId) =>
      '${envPrefixFor(exchangeId)}_API_SECRET';

  static String apiTokenEnvName(String exchangeId) =>
      '${envPrefixFor(exchangeId)}_API_TOKEN';

  static String tradingModeEnvName(String exchangeId) =>
      '${envPrefixFor(exchangeId)}_TRADING_MODE';

  static Future<ExchangeCredentialsConfig> load({
    AssetBundle? bundle,
    List<String>? exchangeIds,
  }) async {
    final values = await DotEnvAsset.load(bundle: bundle);
    return fromValues(
      values,
      exchangeIds: exchangeIds ?? defaultExchangeIds,
    );
  }

  static ExchangeCredentialsConfig fromValues(
    Map<String, String> values, {
    List<String>? exchangeIds,
  }) {
    final ids = exchangeIds ?? defaultExchangeIds;
    final byId = <String, ExchangeCredentials>{};
    for (final id in ids) {
      final creds = read(id, values);
      if (creds.isConfigured ||
          creds.hasApiSecret ||
          creds.tradingMode != null) {
        byId[id] = creds;
      }
    }
    return ExchangeCredentialsConfig(byId);
  }

  /// Read credentials for one exchange id from an already-parsed env map.
  static ExchangeCredentials read(
    String exchangeId,
    Map<String, String> values,
  ) {
    return ExchangeCredentials(
      apiKey: _nonEmpty(values[apiKeyEnvName(exchangeId)]),
      apiSecret: _nonEmpty(values[apiSecretEnvName(exchangeId)]),
      apiToken: _nonEmpty(values[apiTokenEnvName(exchangeId)]),
      tradingMode: VenueTradingModeX.tryParse(
        values[tradingModeEnvName(exchangeId)],
      ),
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
