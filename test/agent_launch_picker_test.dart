import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('single connected investigate agent opens chat without picker',
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
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
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
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<TradeProposalRepository>.value(
            value: proposals,
          ),
          ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
          Provider<GenkitAgentRunner>.value(
            value: fakeGenkitAgentRunner(),
          ),
          ChangeNotifierProvider<EnvSecretsRepository>.value(
            value: EnvSecretsRepository(store: store, syncEnvFile: false),
          ),
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
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Investigate with'), findsNothing);
    expect(find.byType(AgentChatScreen), findsOneWidget);
  });
}
