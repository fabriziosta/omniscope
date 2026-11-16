import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
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
  });
}
