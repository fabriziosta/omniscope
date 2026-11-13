import '../market/exchange_credentials.dart';
import '../venues/venue_trading_mode.dart';
import 'data_source_settings.dart';
import 'env_secrets_repository.dart';

/// Stable select key for exchange credential *presence* (not secret values).
///
/// Use with `context.select` so LLM key edits do not rebuild portfolio/agents.
String exchangeCredsFingerprint(EnvSecretsRepository secrets) {
  final parts = <String>[];
  for (final id in ExchangeCredentialsConfig.defaultExchangeIds) {
    final c = secrets.exchangeCredentialsFor(id);
    parts.add(
      '$id:${c.hasApiKey}:${c.hasApiSecret}:${c.hasApiToken}:'
      '${c.tradingMode?.apiValue ?? ''}',
    );
  }
  return parts.join('|');
}

/// Stable select key for enabled/disabled data-source toggles.
String dataSourceFingerprint(DataSourceSettings settings) {
  final markets = settings.disabledMarketIds.toList()..sort();
  final crypto = settings.disabledCryptoIds.toList()..sort();
  final brokers = settings.disabledBrokerIds.toList()..sort();
  return '${markets.join(',')}|${crypto.join(',')}|${brokers.join(',')}';
}
