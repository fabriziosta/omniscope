import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_model_catalog.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';
import 'package:omniscope/data/settings/user_config_migrations.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _manifestFixture = '''
{
  "version": 1,
  "roles": [
    {
      "id": "marketResearch",
      "title": "Market Research",
      "description": "Research",
      "framework": "genkit",
      "workload": "investigation",
      "suggestedModels": { "openAi": "gpt-test" }
    },
    {
      "id": "intradayTrading",
      "title": "Trading",
      "description": "Trade",
      "framework": "genkit",
      "workload": "trading",
      "suggestedModels": { "openAi": "gpt-heavy" }
    }
  ]
}
''';

const _modelsFixture = '''
{
  "version": 1,
  "providers": {
    "openAi": [
      { "id": "gpt-test", "label": "Test", "default": true, "weight": "light" },
      { "id": "gpt-heavy", "label": "Heavy", "weight": "heavy" }
    ]
  }
}
''';

Future<void> _loadRepos(UserConfigStore store) async {
  final roles = AgentRoleCatalog.parse(_manifestFixture);
  final catalog = LlmModelCatalog.parse(_modelsFixture);
  final agents = AgentsRepository(store: store, roleCatalog: roles);
  await agents.load(roleCatalog: roles);
  final llmRuntime = LlmRuntimeSettings(store: store);
  await llmRuntime.load();
  final agentApp = AgentAppSettings(store: store);
  await agentApp.load();
  final chats = AgentChatRepository(store: store, appSettings: agentApp);
  await chats.load();

  await UserConfigMigrations.runOnce(
    config: store,
    agents: agents,
    llmRuntime: llmRuntime,
    agentApp: agentApp,
    chats: chats,
    llmModels: catalog,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1 fixture migrates to v2 once; second runOnce is no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final store = UserConfigStore(memoryOnly: true);
    await store.importJson(jsonEncode({
      'version': 1,
      UserConfigKeys.agents: {
        'connections': [
          {
            'roleId': 'marketResearch',
            'llmProvider': 'openAi',
            'apiKey': 'sk-legacy',
            'modelId': 'gpt-test',
            'connected': true,
          },
        ],
      },
      UserConfigKeys.agentChats: {
        'threads': [
          {
            'roleId': 'marketResearch',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'messages': <Map<String, dynamic>>[],
          },
        ],
      },
      UserConfigKeys.mandate: {
        'goal': 'grow',
        'maxSymbolCount': 6,
      },
      UserConfigKeys.agentApp: {
        'autopilotEnabled': true,
        'answerMood': 'coaching',
        'disabledRoleIds': ['intradayTrading'],
      },
    }));

    expect(store.getSlice(UserConfigKeys.version), 1);

    await _loadRepos(store);

    expect(store.getSlice(UserConfigKeys.version), 2);

    final chatsSlice = store.getSlice(UserConfigKeys.agentChats) as Map;
    final threadJson = (chatsSlice['threads'] as List).single as Map;
    expect(threadJson['chatId'], 'legacy_marketResearch');
    expect(threadJson.containsKey('roleId'), isFalse);
    expect(threadJson.containsKey('legacyRoleId'), isFalse);
    expect(threadJson['autopilotEnabled'], isTrue);
    expect(threadJson['mandate'], isA<Map>());

    final agentsSlice = store.getSlice(UserConfigKeys.agents) as Map;
    expect(agentsSlice['connections'], isEmpty);

    final mandate = store.getSlice(UserConfigKeys.mandate) as Map;
    expect(mandate.isEmpty, isTrue);

    final appSlice = store.getSlice(UserConfigKeys.agentApp) as Map;
    expect(appSlice['autopilotEnabled'], isFalse);

    final roles = AgentRoleCatalog.parse(_manifestFixture);
    final catalog = LlmModelCatalog.parse(_modelsFixture);
    final agents = AgentsRepository(store: store, roleCatalog: roles);
    await agents.load(roleCatalog: roles);
    final llmRuntime = LlmRuntimeSettings(store: store);
    await llmRuntime.load();
    final agentApp = AgentAppSettings(store: store);
    await agentApp.load();
    final chats = AgentChatRepository(store: store, appSettings: agentApp);
    await chats.load();

    final ranAgain = await UserConfigMigrations.runOnce(
      config: store,
      agents: agents,
      llmRuntime: llmRuntime,
      agentApp: agentApp,
      chats: chats,
      llmModels: catalog,
    );
    expect(ranAgain, isFalse);
    expect(store.getSlice(UserConfigKeys.version), 2);
  });
}
