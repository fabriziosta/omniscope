import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_memory_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';
import 'package:omniscope/features/agents/agents_screen.dart';
import 'package:omniscope/widgets/agent_launch_button.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
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
      framework: AgentFramework.genkit,
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'liveBalanceExplainer',
      title: 'Live Balance Explainer',
      description: 'Explain balances',
      framework: AgentFramework.genkit,
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'portfolioGuide',
      title: 'Portfolio & Allocation Guide',
      description: 'Allocation review',
      framework: AgentFramework.genkit,
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'intradayTrading',
      title: 'Intraday Execution & Risk Control',
      description: 'Trade check',
      framework: AgentFramework.genkit,
      workload: AgentWorkload.trading,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'cryptoSpotGuide',
      title: 'Crypto Spot Primer',
      description: 'Spot literacy',
      framework: AgentFramework.genkit,
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
    const AgentRoleDefinition(
      id: 'marketsLiteracy',
      title: 'Markets & Instruments Tutor',
      description: 'Markets literacy',
      framework: AgentFramework.genkit,
      workload: AgentWorkload.investigation,
      suggestedModels: {},
    ),
  ];

  group('AgentLaunchResolver', () {
    test('maps investigate to market research', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.investigate,
      );
      expect(
        roles.map((r) => r.id).toList(),
        ['marketResearch'],
      );
    });

    test('maps tradeCheck to intraday trading', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.tradeCheck,
      );
      expect(
        roles.map((r) => r.id).toList(),
        ['intradayTrading'],
      );
    });

    test('maps explainLive to live balance explainer', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.explainLive,
      );
      expect(roles.map((r) => r.id).toList(), ['liveBalanceExplainer']);
      expect(AgentLaunchIntent.explainLive.ctaLabel, 'Explain balances');
    });

    test('maps explainPortfolio to portfolio guide', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.explainPortfolio,
      );
      expect(roles.map((r) => r.id).toList(), ['portfolioGuide']);
      expect(AgentLaunchIntent.explainPortfolio.ctaLabel, 'Review portfolio');
      expect(AgentLaunchIntent.explainPortfolio.isPortfolioLevel, isTrue);
    });

    test('maps explainCryptoSpot to crypto spot guide', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.explainCryptoSpot,
      );
      expect(roles.map((r) => r.id).toList(), ['cryptoSpotGuide']);
      expect(AgentLaunchIntent.explainCryptoSpot.ctaLabel, 'Spot primer');
      expect(AgentLaunchIntent.explainCryptoSpot.allowsOptionalSymbol, isTrue);
    });

    test('maps explainMarketsLiteracy to markets literacy', () {
      final roles = AgentLaunchResolver.rolesForIntent(
        availableRoles: sampleRoles,
        intent: AgentLaunchIntent.explainMarketsLiteracy,
      );
      expect(roles.map((r) => r.id).toList(), ['marketsLiteracy']);
      expect(AgentLaunchIntent.explainMarketsLiteracy.ctaLabel, 'Markets tutor');
      expect(
        AgentLaunchIntent.explainMarketsLiteracy.allowsOptionalSymbol,
        isTrue,
      );
    });

    test('chatTitle uses asset and portfolio labels', () {
      expect(
        AgentLaunchIntent.investigate.chatTitle(symbol: 'AAPL'),
        'Investigate asset AAPL',
      );
      expect(
        AgentLaunchIntent.tradeCheck.chatTitle(symbol: 'BTC_USD'),
        'Trade check for BTC_USD',
      );
      expect(
        AgentLaunchIntent.explainLive.chatTitle(portfolioLabel: 'Crypto.com'),
        'Explain balances for Crypto.com',
      );
      expect(
        AgentLaunchIntent.explainPortfolio.chatTitle(),
        'Portfolio review for Practice',
      );
      expect(
        AgentLaunchIntent.explainCryptoSpot.chatTitle(symbol: 'BTC_USD'),
        'Crypto spot primer for BTC_USD',
      );
      expect(
        AgentLaunchIntent.explainMarketsLiteracy.chatTitle(),
        'Markets tutor',
      );
    });
  });

  Future<({int Function() agentCallCount, ShellNavigationController shellNav})>
      pumpLaunchHarness(WidgetTester tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    final seeded = await seedLlmStack(
      store,
      lightModelId: 'gpt-test',
      heavyModelId: 'gpt-test',
    );
    final llmRuntime = seeded.llmRuntime;
    final agentApp = seeded.appSettings;
    final secrets = seeded.secrets;
    final agentChats = AgentChatRepository(store: store);
    await agentChats.load();
    final proposals = TradeProposalRepository(store: store);
    await proposals.load();
    final activity = AgentActivityRepository(store: store);
    await activity.load();
    final investInterest = InvestInterestProposalRepository(store: store);
    await investInterest.load();
    final agentMemory = AgentMemoryRepository(store: store);
    await agentMemory.load();
    final notifications = AppNotificationRepository(store: store);
    await notifications.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final favorites = FavoritesRepository(store: store);
    await favorites.load();
    const cryptoRegistry = CryptoExchangeRegistry([]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final marketData = _agentMarketData();
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: dataSources,
      portfolio: portfolio,
      marketData: marketData,
    );

    var agentCalls = 0;
    final agentRunner = fakeGenkitAgentRunner(
      replyFor: (lastUser) {
        agentCalls++;
        return 'Brief';
      },
    );
    final agentSchedule = AgentScheduleCoordinator(
      agents: agents,
      chats: agentChats,
      marketData: marketData,
      agentRunner: agentRunner,
      tradeExecutor: tradeExecutor,
      proposals: proposals,
      activity: activity,
      notifications: notifications,
      cryptoRegistry: cryptoRegistry,
      dataSources: dataSources,
      portfolio: portfolio,
      favorites: favorites,
      secrets: secrets,
      llmRuntime: llmRuntime,
      appSettings: agentApp,
      agentMemory: agentMemory,
      investInterestProposals: investInterest,
    );
    final shellNav = ShellNavigationController();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      agentSchedule.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(value: marketData),
          Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
          Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
          Provider<TradeExecutor>.value(value: tradeExecutor),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<LlmRuntimeSettings>.value(value: llmRuntime),
          ChangeNotifierProvider<AgentAppSettings>.value(value: agentApp),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<AgentMemoryRepository>.value(value: agentMemory),
          ChangeNotifierProvider<TradeProposalRepository>.value(
            value: proposals,
          ),
          ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
          ChangeNotifierProvider<InvestInterestProposalRepository>.value(
            value: investInterest,
          ),
          ChangeNotifierProvider<AppNotificationRepository>.value(
            value: notifications,
          ),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: secrets),
          Provider<GenkitAgentRunner>.value(value: agentRunner),
          ChangeNotifierProvider<AgentScheduleCoordinator>.value(
            value: agentSchedule,
          ),
          ChangeNotifierProvider<ShellNavigationController>.value(
            value: shellNav,
          ),
        ],
        child: ShadApp(
          home: Builder(
            builder: (context) {
              return ColoredBox(
                color: BrandColors.lightScheme().background,
                child: Column(
                  children: [
                    const Expanded(child: AgentsScreen()),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ShadButton(
                            onPressed: () {
                              AgentLaunchActions.launch(
                                context,
                                intent: AgentLaunchIntent.investigate,
                                symbol: 'AAPL',
                              );
                            },
                            child: const Text('Launch investigate'),
                          ),
                          ShadButton(
                            onPressed: () {
                              AgentLaunchActions.launch(
                                context,
                                intent: AgentLaunchIntent.tradeCheck,
                                symbol: 'AAPL',
                              );
                            },
                            child: const Text('Launch trade'),
                          ),
                          ShadButton(
                            onPressed: () {
                              AgentLaunchActions.launch(
                                context,
                                intent: AgentLaunchIntent.explainPortfolio,
                              );
                            },
                            child: const Text('Launch portfolio review'),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    return (agentCallCount: () => agentCalls, shellNav: shellNav);
  }

  Future<void> expectComposerDraft(
    WidgetTester tester, {
    required String roleId,
    String symbol = '',
    required int Function() agentCallCount,
  }) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: roleId,
      symbol: symbol,
    );
    expect(find.byType(AgentChatScreen), findsOneWidget);
    final inputs = tester.widgetList<ShadInput>(find.byType(ShadInput));
    final composer = inputs.cast<ShadInput?>().firstWhere(
          (input) => input?.controller?.text == draft,
          orElse: () => null,
        );
    expect(composer, isNotNull);
    expect(composer!.controller!.text, draft);
    expect(agentCallCount(), 0);
  }

  testWidgets('Investigate CTA shows Investigate and Trade check menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(
            child: AgentLaunchButton(
              symbol: 'AAPL',
              intent: AgentLaunchIntent.investigate,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Investigate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Investigate'), findsWidgets);
    expect(find.text('Trade check'), findsOneWidget);
  });

  testWidgets(
      'Spot primer CTA shows Spot primer, Investigate, and Trade check',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(
            child: AgentLaunchButton(
              symbol: 'BTC_USD',
              intent: AgentLaunchIntent.explainCryptoSpot,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Spot primer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Spot primer'), findsWidgets);
    expect(find.text('Investigate'), findsOneWidget);
    expect(find.text('Trade check'), findsOneWidget);
  });

  testWidgets(
      'in-app launches draft composer without sending (research/trade/portfolio)',
      (tester) async {
    final harness = await pumpLaunchHarness(tester);
    final chats = tester.element(find.byType(AgentsScreen))
        .read<AgentChatRepository>();

    await tester.tap(find.text('Launch investigate'));
    await expectComposerDraft(
      tester,
      roleId: 'marketResearch',
      symbol: 'AAPL',
      agentCallCount: harness.agentCallCount,
    );
    expect(chats.threads.length, 1);
    expect(chats.threads.single.title, 'Investigate asset AAPL');

    await tester.tap(find.text('Launch trade'));
    await expectComposerDraft(
      tester,
      roleId: 'intradayTrading',
      symbol: 'AAPL',
      agentCallCount: harness.agentCallCount,
    );
    expect(chats.threads.length, 2);
    expect(
      chats.threads.map((t) => t.title),
      containsAll([
        'Investigate asset AAPL',
        'Trade check for AAPL',
      ]),
    );

    // Second Trade check reuses the empty intent chat (no duplicate).
    await tester.tap(find.text('Launch trade'));
    await expectComposerDraft(
      tester,
      roleId: 'intradayTrading',
      symbol: 'AAPL',
      agentCallCount: harness.agentCallCount,
    );
    expect(chats.threads.length, 2);
    expect(
      chats.threads.where((t) => t.title == 'Trade check for AAPL').length,
      1,
    );

    await tester.tap(find.text('Launch portfolio review'));
    await expectComposerDraft(
      tester,
      roleId: 'portfolioGuide',
      agentCallCount: harness.agentCallCount,
    );
    expect(chats.threads.length, 3);
    expect(
      chats.threads.map((t) => t.title),
      contains('Portfolio review for Practice'),
    );
  });
}
