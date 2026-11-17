import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_api_key_config.dart';
import 'package:omniscope/data/agents/llm_model_catalog.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

const _manifestFixture = '''
{
  "version": 1,
  "roles": [
    {
      "id": "marketResearch",
      "title": "Market Research & Analysis",
      "description": "Research brief",
      "framework": "genkit",
      "workload": "investigation",
      "suggestedModels": {
        "openAi": "gpt-6-luna",
        "gemini": "gemini-3.5-flash-lite"
      },
      "suggestionNote": "Prefer a lighter model."
    },
    {
      "id": "intradayTrading",
      "title": "Intraday Execution & Risk Control",
      "description": "Risk gates",
      "framework": "genkit",
      "workload": "trading",
      "suggestedModels": {
        "openAi": "gpt-6-astra",
        "gemini": "gemini-3.8-flash"
      },
      "suggestionNote": "Prefer a heavier model."
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LlmApiKeyConfig', () {
    test('fromValues maps provider keys and ignores empty', () {
      final config = LlmApiKeyConfig.fromValues({
        'OMNISCOPE_OPENAI_API_KEY': 'sk-openai',
        'OMNISCOPE_GEMINI_API_KEY': '',
        'OMNISCOPE_ANTHROPIC_API_KEY': 'sk-claude',
        'OMNISCOPE_DEEPSEEK_API_KEY': 'ds-key',
        'OMNISCOPE_CRYPTO_COM_API_KEY': 'cdc-key',
        'UNKNOWN_KEY': 'nope',
      });
      expect(config.keyFor(LlmProvider.openAi), 'sk-openai');
      expect(config.keyFor(LlmProvider.gemini), isNull);
      expect(config.keyFor(LlmProvider.anthropic), 'sk-claude');
      expect(config.keyFor(LlmProvider.deepSeek), 'ds-key');
      expect(config.keyFor(LlmProvider.grok), isNull);
      expect(
        LlmApiKeyConfig.envNameFor(LlmProvider.openAi),
        'OMNISCOPE_OPENAI_API_KEY',
      );
    });
  });

  group('AgentRoleCatalog', () {
    test('parses roles, frameworks, workloads, and model presets', () {
      final catalog = AgentRoleCatalog.parse(_manifestFixture);
      expect(catalog.roles, hasLength(2));

      final research = catalog.byId('marketResearch')!;
      expect(research.framework, AgentFramework.genkit);
      expect(research.workload, AgentWorkload.investigation);
      expect(research.suggestedModelId(LlmProvider.openAi), 'gpt-6-luna');
      expect(research.workload.preferredModelWeight, ModelWeight.light);

      final trading = catalog.byId('intradayTrading')!;
      expect(trading.framework, AgentFramework.genkit);
      expect(trading.workload, AgentWorkload.trading);
      expect(trading.suggestedModelId(LlmProvider.openAi), 'gpt-6-astra');
      expect(trading.workload.preferredModelWeight, ModelWeight.heavy);
    });
  });

  group('LlmModelCatalog', () {
    test('parses curated providers, defaults, and weights', () {
      const raw = '''
{
  "version": 1,
  "providers": {
    "gemini": [
      { "id": "gemini-3.8-flash", "label": "Gemini 3.8 Flash", "default": true, "weight": "heavy" },
      { "id": "gemini-3.5-flash-lite", "label": "Gemini 3.5 Flash-Lite", "weight": "light" }
    ],
    "openAi": [
      { "id": "gpt-6-luna", "label": "GPT-6 Luna", "default": true, "weight": "light" },
      { "id": "gpt-6-astra", "label": "GPT-6 Astra", "weight": "heavy" }
    ],
    "anthropic": [
      { "id": "claude-sonnet-5-5", "label": "Claude Sonnet 5.5", "default": true, "weight": "heavy" }
    ],
    "deepSeek": [
      { "id": "deepseek-flash", "label": "DeepSeek Flash", "default": true, "weight": "light" }
    ],
    "grok": [
      { "id": "grok-4.7", "label": "Grok 4.7", "default": true, "weight": "heavy" }
    ]
  }
}
''';
      final catalog = LlmModelCatalog.parse(raw);
      expect(catalog.defaultModelId(LlmProvider.openAi), 'gpt-6-luna');
      expect(
        catalog.suggestedModelId(
          LlmProvider.openAi,
          preferredId: 'gpt-6-astra',
          preferredWeight: ModelWeight.heavy,
        ),
        'gpt-6-astra',
      );
      expect(
        catalog.suggestedModelId(
          LlmProvider.gemini,
          preferredWeight: ModelWeight.light,
        ),
        'gemini-3.5-flash-lite',
      );
    });
  });

  group('AgentsRepository', () {
    test('lists roles from catalog and clears legacy connections', () async {
      final store = await memoryConfig();
      final roles = AgentRoleCatalog.parse(_manifestFixture);
      final repo = AgentsRepository(store: store, roleCatalog: roles);
      await repo.load(roleCatalog: roles);

      expect(repo.availableRoles, hasLength(2));
      expect(repo.forRoleId('marketResearch').connected, isFalse);
      expect(repo.forRoleId('marketResearch').isConfigured, isFalse);

      await store.setSlice(UserConfigKeys.agents, {
        'connections': [
          {
            'roleId': 'marketResearch',
            'llmProvider': 'openAi',
            'apiKey': 'sk-legacy',
            'modelId': 'gpt-legacy',
            'connected': true,
          },
        ],
      });
      await repo.load(roleCatalog: roles);
      expect(repo.forRoleId('marketResearch').connected, isTrue);
      expect(repo.forRoleId('marketResearch').apiKey, 'sk-legacy');

      await repo.clearAllConnections();
      expect(repo.forRoleId('marketResearch').connected, isFalse);
      expect(repo.forRoleId('marketResearch').apiKey, isEmpty);
    });
  });
}
