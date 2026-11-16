import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/llm_api_key_config.dart';
import 'package:omniscope/data/agents/llm_model_router.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/models.dart';

void main() {
  group('LlmModelRouter', () {
    test('prefers highest-priority provider with key and model', () async {
      final runtime = LlmRuntimeSettings();
      await runtime.load();
      await runtime.upsert(
        const LlmProviderRuntimePrefs(
          provider: LlmProvider.openAi,
          lightModelId: 'gpt-light',
          heavyModelId: 'gpt-heavy',
          priority: 20,
        ),
      );
      await runtime.upsert(
        const LlmProviderRuntimePrefs(
          provider: LlmProvider.gemini,
          lightModelId: 'gem-light',
          heavyModelId: 'gem-heavy',
          priority: 10,
        ),
      );

      final keys = LlmApiKeyConfig({
        LlmProvider.gemini: 'gem-key',
        LlmProvider.openAi: 'oa-key',
      });

      final light = LlmModelRouter.resolve(
        weight: ModelWeight.light,
        runtime: runtime,
        keys: keys,
      );
      expect(light?.provider, LlmProvider.gemini);
      expect(light?.modelId, 'gem-light');

      final heavy = LlmModelRouter.resolve(
        weight: ModelWeight.heavy,
        runtime: runtime,
        keys: keys,
      );
      expect(heavy?.provider, LlmProvider.gemini);
      expect(heavy?.modelId, 'gem-heavy');
    });

    test('skips providers without keys and falls back across list', () async {
      final runtime = LlmRuntimeSettings();
      await runtime.load();
      await runtime.upsert(
        const LlmProviderRuntimePrefs(
          provider: LlmProvider.gemini,
          lightModelId: 'gem-light',
          priority: 1,
        ),
      );
      await runtime.upsert(
        const LlmProviderRuntimePrefs(
          provider: LlmProvider.openAi,
          lightModelId: 'oa-light',
          heavyModelId: 'oa-heavy',
          priority: 2,
        ),
      );

      final keys = LlmApiKeyConfig({
        LlmProvider.openAi: 'oa-key',
      });

      final resolved = LlmModelRouter.resolve(
        weight: ModelWeight.light,
        runtime: runtime,
        keys: keys,
      );
      expect(resolved?.provider, LlmProvider.openAi);
      expect(resolved?.modelId, 'oa-light');
    });

    test('falls back to other weight on same provider', () async {
      final runtime = LlmRuntimeSettings();
      await runtime.load();
      await runtime.upsert(
        const LlmProviderRuntimePrefs(
          provider: LlmProvider.anthropic,
          heavyModelId: 'claude-heavy',
          priority: 1,
        ),
      );
      final keys = LlmApiKeyConfig({
        LlmProvider.anthropic: 'key',
      });
      final resolved = LlmModelRouter.resolve(
        weight: ModelWeight.light,
        runtime: runtime,
        keys: keys,
      );
      expect(resolved?.modelId, 'claude-heavy');
    });
  });
}
