import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_chat_client.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/widgets/agent_launch_button.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

FakeMarketDataClient _agentMarketData() => FakeMarketDataClient(
      basePrice: 190,
      fixedName: 'Apple',
      changePercent: 0.012,
      previousClose: 188,
      dataSource: 'Yahoo Finance',
      history: [
        Candle(
          time: DateTime.utc(2026, 1, 1),
          close: 180,
          high: 182,
          low: 178,
        ),
        Candle(
          time: DateTime.utc(2026, 1, 30),
          close: 190,
          high: 192,
          low: 185,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleRoles = [
    const AgentRoleDefinition(
      id: 'marketResearch',
      title: 'Market Research & Analysis',
      description: 'Research brief',
      framework: AgentFramework.crewAi,
      module: 'm',
      packagePath: 'p',
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'intradayTrading',
      title: 'Intraday Execution & Risk Control',
      description: 'Trade check',
      framework: AgentFramework.langGraph,
      module: 'm',
      packagePath: 'p',
      workload: AgentWorkload.trading,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'hedgeFundDesk',
      title: 'Hedge Fund Desk',
      description: 'Desk pipeline',
      framework: AgentFramework.langGraph,
      module: 'm',
      packagePath: 'p',
      workload: AgentWorkload.trading,
      suggestedModels: {},
    ),
  ];

  group('AgentLaunchResolver', () {
    test('maps investigate to research + desk', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.investigate,
      );
      expect(
        roles.map((r) => r.id).toList(),
        ['marketResearch', 'hedgeFundDesk'],
      );
    });

    test('maps tradeCheck to trading + desk', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.tradeCheck,
      );
      expect(
        roles.map((r) => r.id).toList(),
        ['intradayTrading', 'hedgeFundDesk'],
      );
    });

    test('filters to connected roles only', () {
      final connected = AgentLaunchResolver.connectedAmong(
        roles: sampleRoles,
        isConnected: (id) => id == 'marketResearch',
      );
      expect(connected, hasLength(1));
      expect(connected.first.id, 'marketResearch');
    });
  });

  testWidgets('Investigate opens chat and auto-runs for one connected agent',
      (tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    await agents.connect(
      roleId: 'marketResearch',
      llmProvider: LlmProvider.openAi,
      apiKey: 'sk-test',
      modelId: 'gpt-6-luna',
    );
    final agentChats = AgentChatRepository(store: store);
    await agentChats.load();
    final proposals = TradeProposalRepository(store: store);
    await proposals.load();
    final activity = AgentActivityRepository(store: store);
    await activity.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    const cryptoRegistry = CryptoExchangeRegistry([]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: dataSources,
    );

    var llmCalls = 0;
    final llm = LlmChatClient(
      httpClient: MockClient((request) async {
        llmCalls++;
        return http.Response(
          '{"choices":[{"message":{"role":"assistant","content":"Brief"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(value: _agentMarketData()),
          Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
          Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
          Provider<TradeExecutor>.value(value: tradeExecutor),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<TradeProposalRepository>.value(
            value: proposals,
          ),
          ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
          ChangeNotifierProvider<EnvSecretsRepository>.value(
            value: EnvSecretsRepository(store: store, syncEnvFile: false),
          ),
          Provider<LlmChatClient>.value(value: llm),
          ChangeNotifierProvider<ShellNavigationController>(
            create: (_) => ShellNavigationController(),
          ),
        ],
        child: ShadApp(
          home: Builder(
            builder: (context) {
              return ColoredBox(
                color: BrandColors.lightScheme().background,
                child: Center(
                  child: AgentLaunchButton(
                    symbol: 'AAPL',
                    intent: AgentLaunchIntent.investigate,
                  ),
                ),
              );
            },
          ),
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: BrandColors.lightScheme(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Investigate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(find.textContaining('Investigate AAPL'), findsOneWidget);
    expect(llmCalls, greaterThan(0));
  });
}
