import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/chat_agent_settings.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
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

  test('emptyChatWithTitle reuses empty drafts only', () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();

    expect(repo.emptyChatWithTitle('Trade check for AAPL'), isNull);

    final empty = await repo.createChat(title: 'Trade check for AAPL');
    expect(repo.emptyChatWithTitle('Trade check for AAPL')?.chatId, empty.chatId);

    await repo.append(
      chatId: empty.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'sent',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    expect(repo.emptyChatWithTitle('Trade check for AAPL'), isNull);

    final again = await repo.createChat(title: 'Trade check for AAPL');
    final touched = await repo.touchChat(again.chatId);
    expect(touched.updatedAt.isAfter(again.updatedAt) ||
        touched.updatedAt.isAtSameMomentAs(again.updatedAt), isTrue);
    expect(repo.emptyChatWithTitle('Trade check for AAPL')?.chatId, again.chatId);
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

  test('focusSymbols JSON round-trip, pin/unpin, and cap', () async {
    final withFocus = AgentChatThread(
      chatId: 'c_focus',
      title: 'Focus',
      messages: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
      focusSymbols: const ['btc_usd', 'AAPL', 'AAPL', ''],
    );
    final parsed = AgentChatThread.fromJson(withFocus.toJson());
    expect(parsed.focusSymbols, ['BTC_USD', 'AAPL']);
    expect(withFocus.toJson()['focusSymbols'], ['BTC_USD', 'AAPL']);

    final empty = AgentChatThread.empty(chatId: 'c_empty');
    expect(empty.focusSymbols, isEmpty);
    expect(empty.toJson().containsKey('focusSymbols'), isFalse);

    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Pins');
    final before = created.updatedAt;

    final pinned = await repo.pinFocusSymbols(
      created.chatId,
      ['eth_usd', 'AAPL', 'ETH_USD'],
    );
    expect(pinned.focusSymbols, ['ETH_USD', 'AAPL']);
    expect(pinned.updatedAt, before);

    final many = List.generate(
      AgentChatThread.maxFocusSymbols + 3,
      (i) => 'S$i',
    );
    final capped = await repo.pinFocusSymbols(created.chatId, many);
    expect(capped.focusSymbols, hasLength(AgentChatThread.maxFocusSymbols));
    expect(capped.focusSymbols.first, isNot('ETH_USD'));
    expect(capped.focusSymbols.last, 'S${many.length - 1}');

    final unpinned = await repo.unpinFocusSymbols(
      created.chatId,
      [capped.focusSymbols.last],
    );
    expect(unpinned.focusSymbols, isNot(contains(capped.focusSymbols.last)));
    expect(unpinned.focusSymbols.length, AgentChatThread.maxFocusSymbols - 1);

    final replaced = await repo.setFocusSymbols(created.chatId, ['MSFT']);
    expect(replaced.focusSymbols, ['MSFT']);

    final again = AgentChatRepository(store: store);
    await again.load();
    expect(again.threadFor(created.chatId).focusSymbols, ['MSFT']);

    await repo.append(
      chatId: created.chatId,
      message: AgentChatMessage(
        id: 'm1',
        role: AgentChatRole.user,
        content: 'Hi',
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    );
    expect(repo.threadFor(created.chatId).focusSymbols, ['MSFT']);
  });

  test('thread JSON always persists mandate; missing key uses defaults', () {
    final withMandate = AgentChatThread(
      chatId: 'c_m',
      title: 'M',
      messages: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
      mandate: const ChatMandate(
        goal: MandateGoal.grow,
        maxSymbolCount: 7,
      ),
    );
    final json = withMandate.toJson();
    expect(json['mandate'], isA<Map>());
    expect(json['mandate']['goal'], 'grow');
    expect(json['mandate']['maxSymbolCount'], 7);

    final legacy = Map<String, dynamic>.from(json)..remove('mandate');
    final parsed = AgentChatThread.fromJson(legacy);
    expect(parsed.mandate, ChatMandate.defaults);
  });

  test('migrateGlobalMandateIfNeeded seeds threads from legacy slice',
      () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.mandate, {
      'goal': 'grow',
      'horizon': 'long',
      'universe': 'equities',
      'maxSymbolCount': 9,
      'maxOpenProposals': 2,
      'maxAutopilotFillsPerDay': 4,
      'cadencePreference': 'hours4',
    });
    await store.setSlice(UserConfigKeys.agentChats, {
      'version': 2,
      'threads': [
        {
          'chatId': 'c_legacy',
          'title': 'Old',
          'messages': <dynamic>[],
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ],
    });

    final repo = AgentChatRepository(store: store);
    await repo.load();
    expect(repo.threadFor('c_legacy').mandate, ChatMandate.defaults);
    await repo.migrateGlobalMandateIfNeeded();

    final seeded = repo.threadFor('c_legacy').mandate;
    expect(seeded.goal, MandateGoal.grow);
    expect(seeded.horizon, MandateHorizon.long);
    expect(seeded.universe, MandateUniverse.equities);
    expect(seeded.maxSymbolCount, 9);
    expect(seeded.maxOpenProposals, 2);
    expect(seeded.maxAutopilotFillsPerDay, 4);

    final legacySlice = store.getSlice(UserConfigKeys.mandate);
    expect(legacySlice, isA<Map>());
    expect((legacySlice as Map).isEmpty, isTrue);

    final again = AgentChatRepository(store: store);
    await again.load();
    expect(again.threadFor('c_legacy').mandate.maxSymbolCount, 9);
  });

  test('setMandate persists without bumping updatedAt', () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Edit mandate');
    final before = created.updatedAt;
    final next = await repo.setMandate(
      created.chatId,
      const ChatMandate(goal: MandateGoal.preserve, maxSymbolCount: 5),
    );
    expect(next.mandate.goal, MandateGoal.preserve);
    expect(next.mandate.maxSymbolCount, 5);
    expect(next.updatedAt, before);
  });

  test('thread JSON always persists agentSettings; missing key uses defaults',
      () {
    final withSettings = AgentChatThread(
      chatId: 'c_as',
      title: 'AS',
      messages: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
      agentSettings: const ChatAgentSettings(
        answerMood: AgentAnswerMood.concise,
        answerMoodNote: 'Bullets',
        disabledRoleIds: {'cryptoSpotPrimer'},
        autopilotExchangeId: 'practice',
      ),
    );
    final json = withSettings.toJson();
    expect(json['agentSettings'], isA<Map>());
    expect(json['agentSettings']['answerMood'], 'concise');
    expect(json['agentSettings']['answerMoodNote'], 'Bullets');
    expect(json['agentSettings']['disabledRoleIds'], ['cryptoSpotPrimer']);
    expect(json['agentSettings']['autopilotExchangeId'], 'practice');

    final legacy = Map<String, dynamic>.from(json)..remove('agentSettings');
    final parsed = AgentChatThread.fromJson(legacy);
    expect(parsed.agentSettings, ChatAgentSettings.defaults);
  });

  test('migrateGlobalAgentSettingsIfNeeded seeds threads and clears agentApp',
      () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.agentApp, {
      'autopilotEnabled': false,
      'autopilotExchangeId': 'crypto_com',
      'autopilotMaxOpenProposals': 3,
      'disabledRoleIds': ['liveBalance'],
      'overrides': <Map<String, dynamic>>[],
      'scheduleEnabled': false,
      'scheduleInterval': 'hour1',
      'scheduleSymbols': <String>[],
      'scheduleUseInvestInterest': true,
      'answerMood': 'coaching',
      'answerMoodNote': 'Keep it short',
    });
    await store.setSlice(UserConfigKeys.agentChats, {
      'version': 2,
      'threads': [
        {
          'chatId': 'c_legacy_as',
          'title': 'Old',
          'messages': <dynamic>[],
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ],
    });

    final app = AgentAppSettings(store: store);
    await app.load();
    expect(app.hasLegacyChatScopedFields, isTrue);
    expect(app.answerMood, AgentAnswerMood.coaching);
    expect(app.autopilotExchangeId, 'crypto_com');

    final repo = AgentChatRepository(store: store);
    await repo.load();
    expect(repo.threadFor('c_legacy_as').agentSettings, ChatAgentSettings.defaults);

    await repo.migrateGlobalAgentSettingsIfNeeded(app);

    final seeded = repo.threadFor('c_legacy_as').agentSettings;
    expect(seeded.answerMood, AgentAnswerMood.coaching);
    expect(seeded.answerMoodNote, 'Keep it short');
    expect(seeded.disabledRoleIds, {'liveBalance'});
    expect(seeded.autopilotExchangeId, 'crypto_com');

    expect(app.hasLegacyChatScopedFields, isFalse);
    expect(app.answerMood, AgentAnswerMood.plain);
    expect(app.answerMoodNote, isNull);
    expect(app.disabledRoleIds, isEmpty);
    expect(app.autopilotExchangeId, isNull);

    final again = AgentChatRepository(store: store);
    await again.load();
    expect(
      again.threadFor('c_legacy_as').agentSettings.answerMood,
      AgentAnswerMood.coaching,
    );
    await again.migrateGlobalAgentSettingsIfNeeded(app);
    expect(
      again.threadFor('c_legacy_as').agentSettings.answerMood,
      AgentAnswerMood.coaching,
    );
  });

  test('setAgentSettings persists without bumping updatedAt', () async {
    final store = await memoryConfig();
    final repo = AgentChatRepository(store: store);
    await repo.load();
    final created = await repo.createChat(title: 'Edit agent settings');
    final before = created.updatedAt;
    final next = await repo.setAgentSettings(
      created.chatId,
      const ChatAgentSettings(
        answerMood: AgentAnswerMood.formal,
        disabledRoleIds: {'marketsLiteracy'},
        autopilotExchangeId: 'practice',
      ),
    );
    expect(next.agentSettings.answerMood, AgentAnswerMood.formal);
    expect(next.agentSettings.disabledRoleIds, {'marketsLiteracy'});
    expect(next.agentSettings.autopilotExchangeId, 'practice');
    expect(next.updatedAt, before);

    final reloaded = AgentChatRepository(store: store);
    await reloaded.load();
    expect(
      reloaded.threadFor(created.chatId).agentSettings.answerMood,
      AgentAnswerMood.formal,
    );
  });
}
