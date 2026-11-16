import 'llm_api_key_config.dart';
import 'llm_runtime_settings.dart';
import 'models.dart';

/// Resolved provider + model for one Genkit turn.
class LlmResolvedEndpoint {
  const LlmResolvedEndpoint({
    required this.provider,
    required this.apiKey,
    required this.modelId,
    required this.weight,
    this.baseUrl,
  });

  final LlmProvider provider;
  final String apiKey;
  final String modelId;
  final ModelWeight weight;
  final String? baseUrl;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty && modelId.trim().isNotEmpty;
}

/// Picks a provider/model across configured keys for a desired [ModelWeight].
abstract final class LlmModelRouter {
  /// Highest-priority enabled provider that has a key and a model for [weight]
  /// (falls back to the other weight on that provider when needed).
  static LlmResolvedEndpoint? resolve({
    required ModelWeight weight,
    required LlmRuntimeSettings runtime,
    required LlmApiKeyConfig keys,
    String? Function(LlmProvider provider)? customBaseUrl,
  }) {
    for (final prefs in runtime.providers) {
      if (!prefs.enabled) continue;
      final key = keys.keyFor(prefs.provider)?.trim() ?? '';
      if (key.isEmpty) continue;
      final modelId = prefs.resolvedModelId(weight);
      if (modelId == null || modelId.isEmpty) continue;
      if (prefs.provider == LlmProvider.custom) {
        final base = (prefs.baseUrl ?? customBaseUrl?.call(prefs.provider) ?? '')
            .trim();
        if (base.isEmpty) continue;
        return LlmResolvedEndpoint(
          provider: prefs.provider,
          apiKey: key,
          modelId: modelId,
          weight: weight,
          baseUrl: base,
        );
      }
      return LlmResolvedEndpoint(
        provider: prefs.provider,
        apiKey: key,
        modelId: modelId,
        weight: weight,
        baseUrl: prefs.baseUrl,
      );
    }
    return null;
  }

  /// True when at least one provider key can resolve any weight.
  static bool hasAnyEndpoint({
    required LlmRuntimeSettings runtime,
    required LlmApiKeyConfig keys,
  }) {
    return resolve(
          weight: ModelWeight.light,
          runtime: runtime,
          keys: keys,
        ) !=
        null ||
        resolve(
          weight: ModelWeight.heavy,
          runtime: runtime,
          keys: keys,
        ) !=
            null;
  }

}
