import 'package:flutter/services.dart';

import '../../core/dotenv_asset.dart';
import 'models.dart';

/// API keys per [LlmProvider] from env secrets (`.env` + prefs).
///
/// Used to preload the Agents connect dialog. Connecting also writes the key
/// back through EnvSecretsRepository (prefs + best-effort `.env`).
class LlmApiKeyConfig {
  LlmApiKeyConfig(this._keysByProvider);

  LlmApiKeyConfig.empty() : _keysByProvider = const {};

  final Map<LlmProvider, String> _keysByProvider;

  /// Non-empty API key for [provider], if configured.
  String? keyFor(LlmProvider provider) {
    final key = _keysByProvider[provider];
    if (key == null || key.isEmpty) return null;
    return key;
  }

  bool get isEmpty => _keysByProvider.isEmpty;

  /// Env var name for a provider (e.g. [LlmProvider.openAi] → `OMNISCOPE_OPENAI_API_KEY`).
  static String envNameFor(LlmProvider provider) {
    final suffix = switch (provider) {
      LlmProvider.gemini => 'GEMINI',
      LlmProvider.openAi => 'OPENAI',
      LlmProvider.anthropic => 'ANTHROPIC',
      LlmProvider.deepSeek => 'DEEPSEEK',
      LlmProvider.grok => 'GROK',
      LlmProvider.custom => 'CUSTOM',
    };
    return 'OMNISCOPE_${suffix}_API_KEY';
  }

  static Future<LlmApiKeyConfig> load({AssetBundle? bundle}) async {
    final values = await DotEnvAsset.load(bundle: bundle);
    return fromValues(values);
  }

  static LlmApiKeyConfig fromValues(Map<String, String> values) {
    final byProvider = <LlmProvider, String>{};
    for (final provider in LlmProvider.values) {
      final key = values[envNameFor(provider)];
      if (key != null && key.isNotEmpty) {
        byProvider[provider] = key;
      }
    }
    return LlmApiKeyConfig(byProvider);
  }

  /// Parses a raw dotenv string (tests / one-off loads).
  static LlmApiKeyConfig parse(String raw) => fromValues(DotEnvAsset.parse(raw));
}
