import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_memory.dart';
import 'package:omniscope/data/agents/agent_memory_repository.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/genkit/agent_tool_registry.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentChatThread memoryEnabled', () {
    test('defaults on; JSON omits true and persists false', () {
      final on = AgentChatThread.empty(chatId: 'c1');
      expect(on.memoryEnabled, isTrue);
      expect(on.toJson().containsKey('memoryEnabled'), isFalse);
      expect(
        AgentChatThread.fromJson(on.toJson()).memoryEnabled,
        isTrue,
      );

      final off = on.copyWith(memoryEnabled: false);
      expect(off.toJson()['memoryEnabled'], isFalse);
      expect(
        AgentChatThread.fromJson(off.toJson()).memoryEnabled,
        isFalse,
      );

      // Legacy threads without the key stay on.
      final legacy = AgentChatThread.fromJson({
        'chatId': 'c_legacy',
        'title': 'Old',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'messages': <dynamic>[],
      });
      expect(legacy.memoryEnabled, isTrue);
    });
  });

  group('AgentMemoryRepository', () {
    test('CRUD, dedupe, caps, and summary', () async {
      final store = await memoryConfig();
      final repo = AgentMemoryRepository(store: store);
      await repo.load();
      expect(repo.facts, isEmpty);
      expect(repo.toAgentSummary(), isEmpty);

      final a = await repo.addFact(
        'Prefer ETFs',
        source: AgentMemorySource.user,
      );
      expect(a, isNotNull);
      expect(repo.facts, hasLength(1));
      expect(repo.facts.first.source, AgentMemorySource.user);

      // Dedupe by normalized text (updates in place).
      final again = await repo.addFact(
        'prefer etfs',
        source: AgentMemorySource.agent,
      );
      expect(repo.facts, hasLength(1));
      expect(again!.source, AgentMemorySource.agent);
      expect(again.text, 'prefer etfs');

      final b = await repo.addFact('Avoid leverage');
      expect(b, isNotNull);
      expect(repo.facts, hasLength(2));

      expect(
        await repo.addFact('x' * (AgentMemoryRepository.maxFactLength + 1)),
        isNull,
      );

      final summary = repo.toAgentSummary();
      expect(summary, contains('Shared agent memory'));
      expect(summary, contains(b!.id));

      expect(await repo.removeFact(b.id), isTrue);
      expect(repo.facts, hasLength(1));
      expect(await repo.removeFact('prefer etfs'), isTrue);
      expect(repo.facts, isEmpty);

      for (var i = 0; i < AgentMemoryRepository.maxFacts + 5; i++) {
        await repo.addFact('Fact number $i');
      }
      expect(repo.facts, hasLength(AgentMemoryRepository.maxFacts));

      final reloaded = AgentMemoryRepository(store: store);
      await reloaded.load();
      expect(reloaded.facts, hasLength(AgentMemoryRepository.maxFacts));

      await reloaded.clearAll();
      expect(reloaded.facts, isEmpty);
      final slice = store.getSlice(UserConfigKeys.agentMemory);
      expect(slice, isA<Map>());
      expect((slice as Map)['facts'], isEmpty);
    });
  });

  group('Memory prompt / tool gating', () {
    test('memoryPreamble empty when Memory off', () {
      expect(
        AgentRolePrompts.memoryPreamble(
          'Shared agent memory:\n- note',
          memoryEnabled: false,
        ),
        isEmpty,
      );
      expect(
        AgentRolePrompts.memoryPreamble(null, memoryEnabled: true),
        contains('rememberFact'),
      );
      expect(
        AgentRolePrompts.memoryPreamble(
          'Shared agent memory:\n- prefer cash',
          memoryEnabled: true,
        ),
        contains('prefer cash'),
      );
    });

    test('toolIdsForRole omits memory tools when Memory off', () {
      final on = AgentToolRegistry.toolIdsForRole('marketResearch');
      expect(on, contains(AgentToolIds.getAgentMemory));
      expect(on, contains(AgentToolIds.rememberFact));
      expect(on, contains(AgentToolIds.forgetFact));

      final off = AgentToolRegistry.toolIdsForRole(
        'marketResearch',
        memoryEnabled: false,
      );
      expect(off, isNot(contains(AgentToolIds.getAgentMemory)));
      expect(off, isNot(contains(AgentToolIds.rememberFact)));
      expect(off, isNot(contains(AgentToolIds.forgetFact)));
      expect(off, contains(AgentToolIds.getQuotes));

      final described = AgentToolRegistry.describeToolsForRole(
        'marketResearch',
        memoryEnabled: false,
      );
      expect(described, isNot(contains(AgentToolIds.rememberFact)));
    });
  });
}
