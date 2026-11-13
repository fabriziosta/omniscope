import 'package:flutter/services.dart';

import '../../core/dotenv_asset.dart';

/// API credentials for a market data venue or crypto exchange.
///
/// Sourced from env secrets (`.env` bootstrap + Settings UI). Public market
/// endpoints (Yahoo, Crypto.com public REST) work without these; keys enable
/// authenticated / private APIs when a client supports them.
class ExchangeCredentials {
  const ExchangeCredentials({
    this.apiKey,
    this.apiSecret,
    this.apiToken,
  });

  final String? apiKey;
  final String? apiSecret;

  /// Bearer / access token for venues that use token auth instead of key+secret.
  final String? apiToken;

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;
  bool get hasApiSecret => apiSecret != null && apiSecret!.isNotEmpty;
  bool get hasApiToken => apiToken != null && apiToken!.isNotEmpty;

  /// True when at least one usable credential field is set.
  bool get isConfigured => hasApiKey || hasApiToken;

  static const empty = ExchangeCredentials();

  ExchangeCredentials copyWith({
    String? apiKey,
    String? apiSecret,
    String? apiToken,
    bool clearApiKey = false,
    bool clearApiSecret = false,
    bool clearApiToken = false,
  }) {
    return ExchangeCredentials(
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      apiSecret: clearApiSecret ? null : (apiSecret ?? this.apiSecret),
      apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
    );
  }
}

/// Exchange/market credentials keyed by venue id.
///
/// Env names follow `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` where
/// `EXCHANGE_ID` is the venue id uppercased (`crypto_com` → `CRYPTO_COM`).
class ExchangeCredentialsConfig {
  ExchangeCredentialsConfig(this._byExchangeId);

  ExchangeCredentialsConfig.empty() : _byExchangeId = const {};

  /// Venues read from `.env` by default (extend when registering a new client).
  static const defaultExchangeIds = ['crypto_com'];

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

  static Future<ExchangeCredentialsConfig> load({
    AssetBundle? bundle,
    List<String> exchangeIds = defaultExchangeIds,
  }) async {
    final values = await DotEnvAsset.load(bundle: bundle);
    return fromValues(values, exchangeIds: exchangeIds);
  }

  static ExchangeCredentialsConfig fromValues(
    Map<String, String> values, {
    List<String> exchangeIds = defaultExchangeIds,
  }) {
    final byId = <String, ExchangeCredentials>{};
    for (final id in exchangeIds) {
      final creds = read(id, values);
      if (creds.isConfigured || creds.hasApiSecret) {
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
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
