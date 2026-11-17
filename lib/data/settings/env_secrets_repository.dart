import 'package:flutter/foundation.dart';

import '../agents/llm_api_key_config.dart';
import '../agents/models.dart';
import '../market/exchange_credentials.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// On-device secrets store backed by the config `secrets` slice.
///
/// Map keys use the `OMNISCOPE_*` naming convention (LLM + venue credentials).
/// Durable storage is [UserConfigStore] (`omniscope.json` / Web prefs blob) —
/// there is no `.env` file bootstrap or dual-write.
class EnvSecretsRepository extends ChangeNotifier {
  EnvSecretsRepository({
    this.store,
    this.onExchangeCredentialsChanged,
  });

  /// Legacy prefs key (migration / tests that still reference the name).
  static const storageKey = UserConfigKeys.legacySecrets;

  UserConfigStore? store;

  /// Invoked after exchange credentials change so live clients can refresh.
  final void Function(String exchangeId, ExchangeCredentials credentials)?
      onExchangeCredentialsChanged;

  final Map<String, String> _values = {};
  bool _ready = false;

  bool get isReady => _ready;

  LlmApiKeyConfig get llmKeys => LlmApiKeyConfig.fromValues(_values);

  ExchangeCredentialsConfig get exchangeCredentials =>
      ExchangeCredentialsConfig.fromValues(
        _values,
        exchangeIds: ExchangeCredentialsConfig.defaultExchangeIds,
      );

  String? llmKeyFor(LlmProvider provider) => llmKeys.keyFor(provider);

  ExchangeCredentials exchangeCredentialsFor(String exchangeId) =>
      ExchangeCredentialsConfig.read(exchangeId, _values);

  /// Load secrets from the config `secrets` slice.
  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _values.clear();

    final slice = this.store?.getSlice(UserConfigKeys.secrets);
    if (slice is Map) {
      final overlay = <String, String>{};
      for (final entry in slice.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        if (key.isNotEmpty) overlay[key] = value;
      }
      _applyOverlay(overlay);
    }

    _ready = true;
    notifyListeners();
  }

  /// Persist an LLM provider key into the config file.
  Future<void> setLlmApiKey(LlmProvider provider, String apiKey) async {
    final name = LlmApiKeyConfig.envNameFor(provider);
    await _setValues({name: apiKey.trim()});
  }

  /// Clear every LLM provider API key (Settings → Data & privacy).
  Future<void> clearAllLlmApiKeys() async {
    await _setValues({
      for (final provider in LlmProvider.values)
        LlmApiKeyConfig.envNameFor(provider): '',
    });
  }

  /// Persist exchange credentials into the config file.
  Future<void> setExchangeCredentials(
    String exchangeId,
    ExchangeCredentials credentials,
  ) async {
    await _setValues({
      ExchangeCredentialsConfig.apiKeyEnvName(exchangeId):
          credentials.apiKey?.trim() ?? '',
      ExchangeCredentialsConfig.apiSecretEnvName(exchangeId):
          credentials.apiSecret?.trim() ?? '',
      ExchangeCredentialsConfig.apiTokenEnvName(exchangeId):
          credentials.apiToken?.trim() ?? '',
      ExchangeCredentialsConfig.tradingModeEnvName(exchangeId):
          credentials.tradingMode?.name ?? '',
    });
    onExchangeCredentialsChanged?.call(
      exchangeId,
      exchangeCredentialsFor(exchangeId),
    );
  }

  /// Clear all credential fields for [exchangeId].
  Future<void> clearExchangeCredentials(String exchangeId) async {
    await setExchangeCredentials(exchangeId, ExchangeCredentials.empty);
  }

  Future<void> _setValues(Map<String, String> updates) async {
    _applyOverlay(updates);
    await _persistSecrets();
    notifyListeners();
  }

  /// Prefs / UI overlay may clear keys with an empty string.
  void _applyOverlay(Map<String, String> overlay) {
    for (final entry in overlay.entries) {
      if (entry.key.isEmpty) continue;
      if (entry.value.isEmpty) {
        _values.remove(entry.key);
      } else {
        _values[entry.key] = entry.value;
      }
    }
  }

  Future<void> _persistSecrets() async {
    // Store the full known secret map so clears survive restarts.
    final payload = <String, String>{};
    for (final provider in LlmProvider.values) {
      final name = LlmApiKeyConfig.envNameFor(provider);
      payload[name] = _values[name] ?? '';
    }
    for (final id in ExchangeCredentialsConfig.defaultExchangeIds) {
      for (final name in [
        ExchangeCredentialsConfig.apiKeyEnvName(id),
        ExchangeCredentialsConfig.apiSecretEnvName(id),
        ExchangeCredentialsConfig.apiTokenEnvName(id),
        ExchangeCredentialsConfig.tradingModeEnvName(id),
      ]) {
        payload[name] = _values[name] ?? '';
      }
    }
    await store?.setSlice(UserConfigKeys.secrets, payload);
  }
}
