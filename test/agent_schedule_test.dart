import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/notifications/app_notification.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
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
        "openAi": "gpt-6-luna"
      }
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentScheduleInterval / symbols', () {
    test('normalizeScheduleSymbols uppercases, splits, and dedupes', () {
      expect(
        normalizeScheduleSymbols(['aapl, btc_usd\nAAPL; eth_usd']),
        ['AAPL', 'BTC_USD', 'ETH_USD'],
      );
      expect(normalizeScheduleSymbols(['  ', ',']), isEmpty);
    });

    test('interval durations and labels', () {
      expect(
        AgentScheduleInterval.minutes15.duration,
        const Duration(minutes: 15),
      );
      expect(AgentScheduleInterval.hour1.shortLabel, '1h');
      expect(AgentScheduleInterval.daily.label, 'Daily');
      expect(
        AgentScheduleIntervalX.parse('hours4'),
        AgentScheduleInterval.hours4,
      );
      expect(
        AgentScheduleIntervalX.parse('nope'),
        AgentScheduleInterval.hour1,
      );
    });
  });

  group('AgentConnection schedule', () {
    test('JSON round-trip preserves schedule fields', () {
      final original = AgentConnection(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        connected: true,
        scheduleEnabled: true,
        scheduleInterval: AgentScheduleInterval.hours4,
        scheduleSymbols: const ['AAPL', 'MSFT'],
        scheduleUseInvestInterest: true,
        scheduleLastRunAt: DateTime.utc(2026, 3, 1, 12),
      );
      final restored = AgentConnection.fromJson(original.toJson());
      expect(restored.scheduleEnabled, isTrue);
      expect(restored.scheduleInterval, AgentScheduleInterval.hours4);
      expect(restored.scheduleSymbols, ['AAPL', 'MSFT']);
      expect(restored.scheduleUseInvestInterest, isTrue);
      expect(restored.scheduleLastRunAt, DateTime.utc(2026, 3, 1, 12));
    });

    test('isScheduleDue respects enabled, symbols, and interval', () {
      final base = AgentConnection(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        connected: true,
        scheduleEnabled: true,
        scheduleInterval: AgentScheduleInterval.hour1,
        scheduleSymbols: const ['AAPL'],
      );
      final now = DateTime.utc(2026, 6, 1, 12);

      expect(base.isScheduleDue(now), isTrue);
      expect(
        base.copyWith(scheduleEnabled: false).isScheduleDue(now),
        isFalse,
      );
      expect(
        base.copyWith(connected: false).isScheduleDue(now),
        isFalse,
      );
      expect(
        base.copyWith(scheduleSymbols: const []).isScheduleDue(now),
        isFalse,
      );
      expect(
        base
            .copyWith(
              scheduleSymbols: const [],
              scheduleUseInvestInterest: true,
            )
            .isScheduleDue(now),
        isTrue,
      );

      final justRan = base.copyWith(scheduleLastRunAt: now);
      expect(justRan.isScheduleDue(now), isFalse);
      expect(
        justRan.isScheduleDue(now.add(const Duration(minutes: 59))),
        isFalse,
      );
      expect(
        justRan.isScheduleDue(now.add(const Duration(hours: 1))),
        isTrue,
      );
    });
  });

  group('AgentRolePrompts invest interest', () {
    test('shared guardrails require Markdown replies', () {
      final role = AgentRolePrompts.forRoleId('marketResearch');
      expect(role, contains('Always format replies as Markdown'));
      expect(role, contains('do not wrap the entire answer in one code fence'));

      final orch = AgentRolePrompts.orchestratorSystem();
      expect(orch, contains('Always format replies as Markdown'));
    });

    test('preamble empty when no symbols', () {
      expect(AgentRolePrompts.investInterestPreamble(const []), isEmpty);
      expect(
        AgentRolePrompts.forRoleId('marketResearch'),
        isNot(contains('invest interest list')),
      );
    });

    test('preamble lists symbols in system prompt', () {
      final text = AgentRolePrompts.forRoleId(
        'marketResearch',
        investInterestSymbols: const ['aapl', 'BTC_USD'],
      );
      expect(text, contains('AAPL, BTC_USD'));
      expect(text, contains('getInvestInterest'));
      expect(text, contains('proposeInvestInterestDiff'));
    });

    test('mandate preamble appended', () {
      final text = AgentRolePrompts.forRoleId(
        'marketResearch',
        mandateSummary: 'Mandate: goal=learn.',
      );
      expect(text, contains('Mandate: goal=learn.'));
      expect(text, contains('getMandate'));
    });

    test('mood preamble includes preset and optional note', () {
      final plain = AgentRolePrompts.forRoleId('marketResearch');
      expect(plain, contains(AgentAnswerMood.plain.systemInstruction));

      final concise = AgentRolePrompts.forRoleId(
        'marketResearch',
        answerMood: AgentAnswerMood.concise,
      );
      expect(concise, contains(AgentAnswerMood.concise.systemInstruction));
      expect(concise, isNot(contains('Extra delivery note')));

      final withNote = AgentRolePrompts.forRoleId(
        'marketResearch',
        answerMood: AgentAnswerMood.coaching,
        answerMoodNote: '  Prefer bullets  ',
      );
      expect(withNote, contains(AgentAnswerMood.coaching.systemInstruction));
      expect(withNote, contains('Prefer bullets'));
      expect(withNote, contains('style only'));

      final blankNote = AgentRolePrompts.moodPreamble(
        mood: AgentAnswerMood.formal,
        note: '   ',
      );
      expect(blankNote, contains(AgentAnswerMood.formal.systemInstruction));
      expect(blankNote, isNot(contains('Extra delivery note')));

      final orch = AgentRolePrompts.orchestratorSystem(
        answerMood: AgentAnswerMood.concise,
        answerMoodNote: 'No slang',
      );
      expect(orch, contains(AgentAnswerMood.concise.systemInstruction));
      expect(orch, contains('No slang'));
    });

    test('supportsInvestInterestProposals roles', () {
      expect(
        AgentRolePrompts.supportsInvestInterestProposals('marketResearch'),
        isTrue,
      );
      expect(
        AgentRolePrompts.supportsInvestInterestProposals('portfolioGuide'),
        isTrue,
      );
      expect(
        AgentRolePrompts.supportsInvestInterestProposals('intradayTrading'),
        isTrue,
      );
      expect(
        AgentRolePrompts.supportsInvestInterestProposals('paperPortfolioCoach'),
        isFalse,
      );
    });
  });

  group('AgentAppSettings answer mood', () {
    test('defaults then persists mood and note', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();

      expect(app.answerMood, AgentAnswerMood.plain);
      expect(app.answerMoodNote, isNull);

      await app.setAnswerMood(AgentAnswerMood.coaching);
      await app.setAnswerMoodNote('  Prefer short sections  ');
      expect(app.answerMood, AgentAnswerMood.coaching);
      expect(app.answerMoodNote, 'Prefer short sections');

      final again = AgentAppSettings(store: store);
      await again.load();
      expect(again.answerMood, AgentAnswerMood.coaching);
      expect(again.answerMoodNote, 'Prefer short sections');

      final slice = store.getSlice(UserConfigKeys.agentApp) as Map;
      expect(slice['answerMood'], 'coaching');
      expect(slice['answerMoodNote'], 'Prefer short sections');

      await again.setAnswerMoodNote('   ');
      expect(again.answerMoodNote, isNull);
      expect(
        (store.getSlice(UserConfigKeys.agentApp) as Map)
            .containsKey('answerMoodNote'),
        isFalse,
      );
    });

    test('normalizeAnswerMoodNote trims and caps length', () {
      expect(AgentAppSettings.normalizeAnswerMoodNote(null), isNull);
      expect(AgentAppSettings.normalizeAnswerMoodNote('  '), isNull);
      expect(AgentAppSettings.normalizeAnswerMoodNote(' hi '), 'hi');
      final long = 'x' * (AgentAppSettings.maxAnswerMoodNoteLength + 40);
      final capped = AgentAppSettings.normalizeAnswerMoodNote(long)!;
      expect(capped.length, AgentAppSettings.maxAnswerMoodNoteLength);
    });
  });

  group('AgentAppSettings schedule', () {
    test('persists schedule and isScheduleDue respects last run', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();

      await app.setSchedule(
        enabled: true,
        interval: AgentScheduleInterval.minutes15,
        symbols: const ['aapl', 'msft'],
        useInvestInterest: false,
      );
      expect(app.scheduleEnabled, isTrue);
      expect(app.scheduleInterval, AgentScheduleInterval.minutes15);
      expect(app.scheduleSymbols, ['AAPL', 'MSFT']);
      expect(app.isScheduleDue(DateTime.utc(2026, 1, 1)), isTrue);

      final stamped = DateTime.utc(2026, 1, 1);
      await app.updateScheduleLastRunAt(stamped);
      expect(app.scheduleLastRunAt, stamped);
      expect(
        app.isScheduleDue(stamped.add(const Duration(minutes: 5))),
        isFalse,
      );
      expect(
        app.isScheduleDue(stamped.add(const Duration(minutes: 15))),
        isTrue,
      );

      await app.setSchedule(enabled: false);
      expect(app.scheduleEnabled, isFalse);
      expect(app.scheduleSymbols, ['AAPL', 'MSFT']);
    });

    test('invest-interest schedule due without typed symbols', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();
      await app.setSchedule(
        enabled: true,
        symbols: const [],
        useInvestInterest: true,
      );
      expect(app.isScheduleDue(DateTime.utc(2026, 1, 1)), isTrue);

      await app.setSchedule(
        enabled: true,
        symbols: const [],
        useInvestInterest: false,
      );
      expect(app.isScheduleDue(DateTime.utc(2026, 1, 1)), isFalse);
    });
  });

  group('AgentScheduleCoordinator', () {
    Future<
        ({
          AgentsRepository agents,
          FavoritesRepository favorites,
          AgentScheduleCoordinator coord,
          AgentActivityRepository activity,
          AgentChatRepository chats,
          AppNotificationRepository notifications,
          AgentAppSettings agentApp,
          ValueGetter<int> agentCalls,
        })> harness({
      void Function()? onAgentCall,
    }) async {
      final store = await memoryConfig();
      final roles = AgentRoleCatalog.parse(_manifestFixture);
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      final favorites = FavoritesRepository(store: store);
      await favorites.load();
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final notifications = AppNotificationRepository(store: store);
      await notifications.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();
      var calls = 0;

      final seeded = await seedLlmStack(
        store,
        lightModelId: 'gpt-test',
        heavyModelId: 'gpt-test',
      );
      final llmRuntime = seeded.llmRuntime;
      final agentApp = seeded.appSettings;
      await agentApp.setSchedule(
        enabled: true,
        useInvestInterest: true,
      );
      final secrets = seeded.secrets;
      final coord = AgentScheduleCoordinator(
        agents: agents,
        chats: chats,
        marketData: market,
        agentRunner: fakeGenkitAgentRunner(
          replyFor: (lastUser) {
            calls++;
            onAgentCall?.call();
            return 'Scheduled brief';
          },
        ),
        tradeExecutor: RoutingTradeExecutor(
          cryptoRegistry: const CryptoExchangeRegistry([]),
          brokerRegistry: BrokerExchangeRegistry.empty,
          dataSources: dataSources,
          portfolio: portfolio,
          marketData: market,
        ),
        proposals: proposals,
        activity: activity,
        notifications: notifications,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
        favorites: favorites,
        secrets: secrets,
        llmRuntime: llmRuntime,
        appSettings: agentApp,
        pollInterval: const Duration(hours: 24),
      );
      return (
        agents: agents,
        favorites: favorites,
        coord: coord,
        activity: activity,
        chats: chats,
        notifications: notifications,
        agentApp: agentApp,
        agentCalls: () => calls,
      );
    }

    test('skips when paused or not due', () async {
      final h = await harness();

      await h.agentApp.setSchedule(
        enabled: true,
        symbols: const ['AAPL'],
        useInvestInterest: false,
      );

      await h.coord.tick(now: DateTime.utc(2026, 6, 1));
      expect(h.agentCalls(), 0);
      expect(h.coord.isPolling, isFalse);

      h.coord.resume();
      expect(h.coord.isResumed, isTrue);

      await h.agentApp.updateScheduleLastRunAt(DateTime.utc(2026, 6, 1));
      await h.coord.tick(now: DateTime.utc(2026, 6, 1, 0, 30));
      expect(h.agentCalls(), 0);

      h.coord.pause();
      expect(h.coord.isResumed, isFalse);
      h.coord.dispose();
    });

    test('runs due symbols when resumed and logs scheduled activity', () async {
      final h = await harness();

      await h.agentApp.setSchedule(
        enabled: true,
        interval: AgentScheduleInterval.hour1,
        symbols: const ['AAPL', 'MSFT'],
        useInvestInterest: false,
      );

      // Avoid resume()'s unawaited catch-up so we control the clock.
      h.coord.debugMarkResumed();
      final now = DateTime.utc(2026, 7, 1, 10);
      await h.coord.tick(now: now);

      expect(h.agentCalls(), 2);
      expect(h.agentApp.scheduleLastRunAt, now);
      expect(h.chats.threads, isNotEmpty);

      final scheduled = h.activity.events
          .where((e) => e.kind == AgentActivityKind.scheduledRun)
          .map((e) => e.symbol)
          .toList();
      expect(scheduled, unorderedEquals(['AAPL', 'MSFT']));

      expect(h.notifications.active, hasLength(2));
      expect(
        h.notifications.active.map((n) => n.symbol).toList(),
        unorderedEquals(['AAPL', 'MSFT']),
      );
      expect(
        h.notifications.active.every(
          (n) => n.kind == AppNotificationKind.scheduledRunCompleted,
        ),
        isTrue,
      );
      expect(
        h.notifications.active.every(
          (n) => n.chatId != null && n.chatId!.isNotEmpty,
        ),
        isTrue,
      );
      expect(h.notifications.unreadCount, 2);

      // Second tick inside the interval must not re-run.
      await h.coord.tick(now: now.add(const Duration(minutes: 10)));
      expect(h.agentCalls(), 2);
      expect(h.notifications.active, hasLength(2));

      h.coord.dispose();
    });

    test('runs invest-interest symbols when flag enabled', () async {
      final h = await harness();
      await h.favorites.toggleInvestInterest('TSLA');
      await h.favorites.toggleInvestInterest('NVDA');

      await h.agentApp.setSchedule(
        enabled: true,
        interval: AgentScheduleInterval.hour1,
        useInvestInterest: true,
        symbols: const ['AAPL'],
      );

      h.coord.debugMarkResumed();
      final now = DateTime.utc(2026, 8, 1, 10);
      await h.coord.tick(now: now);

      expect(h.agentCalls(), 2);
      final scheduled = h.activity.events
          .where((e) => e.kind == AgentActivityKind.scheduledRun)
          .map((e) => e.symbol)
          .toList();
      expect(scheduled, unorderedEquals(['TSLA', 'NVDA']));

      h.coord.dispose();
    });
  });
}
