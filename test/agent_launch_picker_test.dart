import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:omniscope/features/agents/agents_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('investigate launch opens orchestrator chat without picker',
      (tester) async {
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
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final favorites = FavoritesRepository(store: store);
    await favorites.load();
    final mandate = MandateSettings(store: store);
    await mandate.load();
    final marketData = FakeMarketDataClient(
      emptyQuotes: true,
      emptyHistory: true,
    );
    const cryptoRegistry = CryptoExchangeRegistry([]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: dataSources,
      portfolio: portfolio,
      marketData: marketData,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          ChangeNotifierProvider<MandateSettings>.value(value: mandate),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<LlmRuntimeSettings>.value(value: llmRuntime),
          ChangeNotifierProvider<AgentAppSettings>.value(value: agentApp),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<TradeProposalRepository>.value(
            value: proposals,
          ),
          ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
          ChangeNotifierProvider<InvestInterestProposalRepository>.value(
            value: investInterest,
          ),
          Provider<GenkitAgentRunner>.value(
            value: fakeGenkitAgentRunner(),
          ),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: secrets),
          ChangeNotifierProvider<ShellNavigationController>(
            create: (_) => ShellNavigationController(),
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
                      child: ShadButton(
                        onPressed: () {
                          AgentLaunchActions.launch(
                            context,
                            intent: AgentLaunchIntent.investigate,
                            symbol: 'MSFT',
                          );
                        },
                        child: const Text('Go'),
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
    await tester.tap(find.text('Go'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Investigate with'), findsNothing);
    expect(find.byType(AgentChatScreen), findsOneWidget);
  });
}
