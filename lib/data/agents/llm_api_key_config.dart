import 'models.dart';

/// API keys per [LlmProvider] from the config `secrets` map.
///
/// Settings → Agents reads/writes keys through [EnvSecretsRepository].
/// Map keys use [envNameFor] (`OMNISCOPE_*_API_KEY`).
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

  /// Secrets-map key for a provider (e.g. [LlmProvider.openAi] → `OMNISCOPE_OPENAI_API_KEY`).
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
}
