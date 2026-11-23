import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  test('thread JSON round-trips autopilotEnabled', () {
    final on = AgentChatThread(
      chatId: 'c1',
      title: 'A',
      messages: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
      autopilotEnabled: true,
    );
    final parsedOn = AgentChatThread.fromJson(on.toJson());
    expect(parsedOn.autopilotEnabled, isTrue);
    expect(on.toJson().containsKey('autopilotEnabled'), isTrue);

    final off = AgentChatThread.empty(chatId: 'c2');
    final parsedOff = AgentChatThread.fromJson(off.toJson());
    expect(parsedOff.autopilotEnabled, isFalse);
    expect(off.toJson().containsKey('autopilotEnabled'), isFalse);
  });

  test('thread JSON defaults memoryEnabled on; persists off', () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Mem');
    expect(created.memoryEnabled, isTrue);
    expect(created.toJson().containsKey('memoryEnabled'), isFalse);

    final toggled = await repo.setMemoryEnabled(created.chatId, enabled: false);
    expect(toggled.memoryEnabled, isFalse);
    expect(toggled.toJson()['memoryEnabled'], isFalse);

    final again = AgentChatRepository(store: store);
    await again.load();
    expect(again.threadFor(created.chatId).memoryEnabled, isFalse);

    await again.setMemoryEnabled(created.chatId, enabled: true);
    expect(again.threadFor(created.chatId).memoryEnabled, isTrue);
    expect(
      again.threadFor(created.chatId).toJson().containsKey('memoryEnabled'),
      isFalse,
    );
  });

  test('migrates legacy roleId threads to chatId', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.agentChats, {
      'threads': [
        {
          'roleId': 'marketResearch',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'content': 'Investigate AAPL',
              'createdAt': '2026-01-01T00:00:00.000Z',
              'kind': 'run',
            },
          ],
        },
      ],
    });

    final repo = AgentChatRepository(store: store);
    await repo.load();
    expect(repo.threads, hasLength(1));
    final thread = repo.threads.first;
    expect(thread.chatId, 'legacy_marketResearch');
    expect(thread.legacyRoleId, 'marketResearch');
    expect(thread.messages, hasLength(1));
    expect(thread.messages.first.content, 'Investigate AAPL');
  });

  test('createChat and append use chatId', () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Research');
    expect(created.autopilotEnabled, isFalse);
    await repo.append(
      chatId: created.chatId,
      message: AgentChatMessage(
        id: 'm1',
        role: AgentChatRole.user,
        content: 'Hello',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final thread = repo.threadFor(created.chatId);
    expect(thread.title, 'Research');
    expect(thread.messages.single.content, 'Hello');
    expect(thread.autopilotEnabled, isFalse);
  });

  test('setAutopilotEnabled persists without bumping updatedAt and auto-pins',
      () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Trade');
    expect(created.pinned, isFalse);
    final before = created.updatedAt;
    final toggled = await repo.setAutopilotEnabled(
      created.chatId,
      enabled: true,
    );
    expect(toggled.autopilotEnabled, isTrue);
    expect(toggled.pinned, isTrue);
    expect(toggled.updatedAt, before);

    final again = AgentChatRepository(store: store);
    await again.load();
    expect(again.threadFor(created.chatId).autopilotEnabled, isTrue);
    expect(again.threadFor(created.chatId).pinned, isTrue);
  });

  test('setAutopilotEnabled refuses a sixth chat and keeps pin on disable',
      () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final ids = <String>[];
    for (var i = 0; i < AgentChatRepository.maxAutopilotEnabledChats; i++) {
      final chat = await repo.createChat(title: 'AP $i');
      ids.add(chat.chatId);
      final enabled = await repo.setAutopilotEnabled(chat.chatId, enabled: true);
      expect(enabled.autopilotEnabled, isTrue);
      expect(enabled.pinned, isTrue);
    }
    expect(repo.autopilotEnabledCount, AgentChatRepository.maxAutopilotEnabledChats);
    expect(repo.canEnableAutopilot, isFalse);

    final sixth = await repo.createChat(title: 'Over');
    expect(
      repo.autopilotEnableBlockReason(sixth.chatId),
      contains('at most ${AgentChatRepository.maxAutopilotEnabledChats}'),
    );
    final refused = await repo.setAutopilotEnabled(sixth.chatId, enabled: true);
    expect(refused.autopilotEnabled, isFalse);
    expect(refused.pinned, isFalse);
    expect(repo.autopilotEnabledCount, AgentChatRepository.maxAutopilotEnabledChats);

    final firstId = ids.first;
    final disabled = await repo.setAutopilotEnabled(firstId, enabled: false);
    expect(disabled.autopilotEnabled, isFalse);
    expect(disabled.pinned, isTrue);
    expect(repo.canEnableAutopilot, isTrue);
    expect(repo.autopilotEnableBlockReason(sixth.chatId), isNull);

    final nowOn = await repo.setAutopilotEnabled(sixth.chatId, enabled: true);
    expect(nowOn.autopilotEnabled, isTrue);
    expect(nowOn.pinned, isTrue);
  });

  test('migrateGlobalAutopilotIfNeeded seeds threads then clears global',
      () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.agentChats, {
      'version': 2,
      'threads': [
        {
          'chatId': 'c_a',
          'title': 'A',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'messages': <Map<String, dynamic>>[],
        },
        {
          'chatId': 'c_b',
          'title': 'B',
          'updatedAt': '2026-01-02T00:00:00.000Z',
          'messages': <Map<String, dynamic>>[],
          'autopilotEnabled': true,
        },
      ],
    });
    await store.setSlice(UserConfigKeys.agentApp, {
      'autopilotEnabled': true,
      'autopilotExchangeId': 'crypto_com',
      'autopilotMaxOpenProposals': 3,
      'disabledRoleIds': <String>[],
      'overrides': <Map<String, dynamic>>[],
      'scheduleEnabled': false,
      'scheduleInterval': 'hour1',
      'scheduleSymbols': <String>[],
      'scheduleUseInvestInterest': true,
      'answerMood': 'plain',
    });

    final app = AgentAppSettings(store: store);
    await app.load();
    expect(app.autopilotEnabled, isTrue);
    expect(app.autopilotExchangeId, 'crypto_com');

    final repo = AgentChatRepository(store: store);
    await repo.load();
    await repo.migrateGlobalAutopilotIfNeeded(app);

    expect(app.autopilotEnabled, isFalse);
    expect(app.autopilotExchangeId, 'crypto_com');
    expect(repo.threadFor('c_a').autopilotEnabled, isTrue);
    expect(repo.threadFor('c_b').autopilotEnabled, isTrue);

    // Second load must not re-enable global Autopilot.
    final app2 = AgentAppSettings(store: store);
    await app2.load();
    expect(app2.autopilotEnabled, isFalse);
  });

  test('migrateGlobalAutopilotIfNeeded is a no-op when global is off',
      () async {
    final store = await memoryConfig();
    final app = AgentAppSettings(store: store);
    await app.load();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Keep off');
    await repo.migrateGlobalAutopilotIfNeeded(app);
    expect(repo.threadFor(created.chatId).autopilotEnabled, isFalse);
  });
}
