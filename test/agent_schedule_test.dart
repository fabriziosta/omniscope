import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_chat_client.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/notifications/app_notification.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';

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
      "framework": "crewAi",
      "module": "omniscope_agents.market_research",
      "packagePath": "market_research",
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
        scheduleLastRunAt: DateTime.utc(2026, 3, 1, 12),
      );
      final restored = AgentConnection.fromJson(original.toJson());
      expect(restored.scheduleEnabled, isTrue);
      expect(restored.scheduleInterval, AgentScheduleInterval.hours4);
      expect(restored.scheduleSymbols, ['AAPL', 'MSFT']);
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

  group('AgentsRepository schedule', () {
    test('connect rejects schedule without symbols', () async {
      final store = await memoryConfig();
      final roles = AgentRoleCatalog.parse(_manifestFixture);
      final repo = AgentsRepository(store: store, roleCatalog: roles);
      await repo.load(roleCatalog: roles);

      final err = await repo.connect(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        scheduleEnabled: true,
        scheduleSymbols: const [],
      );
      expect(err, contains('symbol'));
    });

    test('connect persists schedule; disconnect clears enabled flag', () async {
      final store = await memoryConfig();
      final roles = AgentRoleCatalog.parse(_manifestFixture);
      final repo = AgentsRepository(store: store, roleCatalog: roles);
      await repo.load(roleCatalog: roles);

      final err = await repo.connect(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        scheduleEnabled: true,
        scheduleInterval: AgentScheduleInterval.minutes15,
        scheduleSymbols: const ['aapl', 'msft'],
      );
      expect(err, isNull);
      var conn = repo.forRoleId('marketResearch');
      expect(conn.scheduleEnabled, isTrue);
      expect(conn.scheduleInterval, AgentScheduleInterval.minutes15);
      expect(conn.scheduleSymbols, ['AAPL', 'MSFT']);

      final stamped = DateTime.utc(2026, 1, 1);
      await repo.updateScheduleLastRunAt('marketResearch', stamped);
      expect(
        repo.forRoleId('marketResearch').scheduleLastRunAt,
        stamped,
      );

      await repo.disconnect('marketResearch');
      conn = repo.forRoleId('marketResearch');
      expect(conn.scheduleEnabled, isFalse);
      expect(conn.scheduleSymbols, ['AAPL', 'MSFT']);
      expect(conn.scheduleLastRunAt, stamped);
    });
  });

  group('AgentScheduleCoordinator', () {
    Future<
        ({
          AgentsRepository agents,
          AgentScheduleCoordinator coord,
          AgentActivityRepository activity,
          AgentChatRepository chats,
          AppNotificationRepository notifications,
        })> _harness({
      required MockClient httpClient,
    }) async {
      final store = await memoryConfig();
      final roles = AgentRoleCatalog.parse(_manifestFixture);
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
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

      final coord = AgentScheduleCoordinator(
        agents: agents,
        chats: chats,
        marketData: market,
        llm: LlmChatClient(httpClient: httpClient),
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
        pollInterval: const Duration(hours: 24),
      );
      return (
        agents: agents,
        coord: coord,
        activity: activity,
        chats: chats,
        notifications: notifications,
      );
    }

    test('skips when paused or not due', () async {
      var llmCalls = 0;
      final h = await _harness(
        httpClient: MockClient((_) async {
          llmCalls++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'Brief',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await h.agents.connect(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        scheduleEnabled: true,
        scheduleSymbols: const ['AAPL'],
      );

      await h.coord.tick(now: DateTime.utc(2026, 6, 1));
      expect(llmCalls, 0);
      expect(h.coord.isPolling, isFalse);

      h.coord.resume();
      expect(h.coord.isResumed, isTrue);

      await h.agents.updateScheduleLastRunAt(
        'marketResearch',
        DateTime.utc(2026, 6, 1),
      );
      await h.coord.tick(now: DateTime.utc(2026, 6, 1, 0, 30));
      expect(llmCalls, 0);

      h.coord.pause();
      expect(h.coord.isResumed, isFalse);
      h.coord.dispose();
    });

    test('runs due symbols when resumed and logs scheduled activity', () async {
      var llmCalls = 0;
      final h = await _harness(
        httpClient: MockClient((_) async {
          llmCalls++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'Scheduled brief',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await h.agents.connect(
        roleId: 'marketResearch',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        scheduleEnabled: true,
        scheduleInterval: AgentScheduleInterval.hour1,
        scheduleSymbols: const ['AAPL', 'MSFT'],
      );

      // Avoid resume()'s unawaited catch-up so we control the clock.
      h.coord.debugMarkResumed();
      final now = DateTime.utc(2026, 7, 1, 10);
      await h.coord.tick(now: now);

      expect(llmCalls, 2);
      expect(
        h.agents.forRoleId('marketResearch').scheduleLastRunAt,
        now,
      );
      expect(h.chats.threadFor('marketResearch').messages, isNotEmpty);

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
      expect(h.notifications.unreadCount, 2);

      // Second tick inside the interval must not re-run.
      await h.coord.tick(now: now.add(const Duration(minutes: 10)));
      expect(llmCalls, 2);
      expect(h.notifications.active, hasLength(2));

      h.coord.dispose();
    });
  });
}
