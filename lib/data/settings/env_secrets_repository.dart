import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/dotenv_asset.dart';
import '../../core/dotenv_file.dart';
import '../agents/llm_api_key_config.dart';
import '../agents/models.dart';
import '../market/exchange_credentials.dart';
import '../venues/venue_trading_mode.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Dual-direction secrets store: `.env` bootstrap + UI edits.
///
/// Load order: bundled asset → live project `.env` (desktop) → config
/// `secrets` overlay. Non-empty bootstrap keys that are missing or empty
/// in the config are promoted into `omniscope.json` on startup so checkout
/// `.env` edits persist for the Flutter app. Saves write the config file;
/// desktop also upserts the project `.env` when writable.
class EnvSecretsRepository extends ChangeNotifier {
  EnvSecretsRepository({
    this.store,
    this.onExchangeCredentialsChanged,
    this.syncEnvFile = true,
  });

  /// Legacy prefs key (migration / tests that still reference the name).
  static const storageKey = UserConfigKeys.legacySecrets;

  UserConfigStore? store;

  /// When false, skip reading/writing the project `.env` (tests).
  final bool syncEnvFile;

  /// Invoked after exchange credentials change so live clients can refresh.
  final void Function(String exchangeId, ExchangeCredentials credentials)?
      onExchangeCredentialsChanged;

  final Map<String, String> _values = {};
  bool _ready = false;

  bool get isReady => _ready;

  /// Whether the project `.env` can be written on this platform/session.
  bool get canWriteEnvFile => syncEnvFile && DotEnvFile.canWrite;

  LlmApiKeyConfig get llmKeys => LlmApiKeyConfig.fromValues(_values);

  ExchangeCredentialsConfig get exchangeCredentials =>
      ExchangeCredentialsConfig.fromValues(
        _values,
        exchangeIds: ExchangeCredentialsConfig.defaultExchangeIds,
      );

  String? llmKeyFor(LlmProvider provider) => llmKeys.keyFor(provider);

  ExchangeCredentials exchangeCredentialsFor(String exchangeId) =>
      ExchangeCredentialsConfig.read(exchangeId, _values);

  /// Bootstrap from asset / filesystem / config secrets slice.
  ///
  /// When [additionalBootstrap] is set (tests), those non-empty values are
  /// merged after `.env` sources.
  Future<void> load({
    UserConfigStore? store,
    AssetBundle? bundle,
    @visibleForTesting Map<String, String>? additionalBootstrap,
  }) async {
    if (store != null) this.store = store;
    _values.clear();

    final assetRaw = await DotEnvAsset.loadRaw(bundle: bundle);
    _merge(DotEnvAsset.parse(assetRaw));

    if (syncEnvFile) {
      final fileRaw = await DotEnvFile.readRaw();
      if (fileRaw != null && fileRaw.isNotEmpty) {
        _merge(DotEnvAsset.parse(fileRaw));
      }
    }

    if (additionalBootstrap != null) {
      _merge(additionalBootstrap);
    }

    // Snapshot before config overlay — these are candidates to promote.
    final bootstrap = Map<String, String>.from(_values);

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

    // Promote .env / asset keys into the config file when missing or empty
    // there, so edits to `.env` survive as durable app settings.
    var needsPersist = slice is! Map && bootstrap.isNotEmpty;
    for (final entry in bootstrap.entries) {
      final configValue =
          slice is Map ? slice[entry.key]?.toString() : null;
      final configHasValue =
          configValue != null && configValue.trim().isNotEmpty;
      if (!configHasValue) {
        _values[entry.key] = entry.value;
        needsPersist = true;
      }
    }

    if (needsPersist && this.store != null) {
      await _persistSecrets();
    }

    _ready = true;
    notifyListeners();
  }

  /// Persist an LLM provider key and sync to `.env` when possible.
  Future<void> setLlmApiKey(LlmProvider provider, String apiKey) async {
    final name = LlmApiKeyConfig.envNameFor(provider);
    await _setValues({name: apiKey.trim()});
  }

  /// Persist exchange credentials and sync to `.env` when possible.
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
          credentials.tradingMode?.apiValue ?? '',
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
    if (syncEnvFile) {
      await DotEnvFile.upsertValues(updates);
    }
    notifyListeners();
  }

  void _merge(Map<String, String> incoming) {
    for (final entry in incoming.entries) {
      if (entry.key.isEmpty || entry.value.isEmpty) continue;
      _values[entry.key] = entry.value;
    }
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
