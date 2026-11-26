import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/app.dart';
import 'package:omniscope/core/app_error_controller.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_memory_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/llm_connection_status_store.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/equity_data_source.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/theme_settings.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/data/venues/venue_catalog.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';
import 'package:provider/provider.dart';

import 'agent_test_harness.dart';
import 'fake_genkit_agent_runner.dart';
import 'fake_market_data_client.dart';
import 'memory_config.dart';

/// Loaded repos + nav for a pumped [OmniscopeApp] in widget tests.
class OmniscopeTestAppContext {
  OmniscopeTestAppContext({
    required this.config,
    required this.shellNav,
    required this.marketData,
    required this.portfolio,
    required this.agents,
    required this.chats,
    required this.secrets,
    required this.llmRuntime,
    required this.appSettings,
    required this.tradeExecutor,
  });

  final UserConfigStore config;
  final ShellNavigationController shellNav;
  final MarketDataClient marketData;
  final PortfolioRepository portfolio;
  final AgentsRepository agents;
  final AgentChatRepository chats;
  final EnvSecretsRepository secrets;
  final LlmRuntimeSettings llmRuntime;
  final AgentAppSettings appSettings;
  final TradeExecutor tradeExecutor;
}

/// Pumps a full [OmniscopeApp] with in-memory config and test doubles.
Future<OmniscopeTestAppContext> pumpOmniscope(
  WidgetTester tester, {
  MarketDataClient? marketData,
  CryptoExchangeRegistry? cryptoRegistry,
  GenkitAgentRunner? agentRunner,
  Size surfaceSize = const Size(390, 844),
  bool seedLlm = true,
}) async {
  final config = await memoryConfig();
  final portfolio = PortfolioRepository(store: config);
  await portfolio.load();
  final themeSettings = ThemeSettings(store: config);
  await themeSettings.load();
  final displaySettings = DisplaySettings(store: config);
  await displaySettings.load();
  final dataSourceSettings = DataSourceSettings(store: config);
  await dataSourceSettings.load();
  final favorites = FavoritesRepository(store: config);
  await favorites.load();
  final agentRoles = await AgentRoleCatalog.load();
  final agents = AgentsRepository(store: config, roleCatalog: agentRoles);
  await agents.load(roleCatalog: agentRoles);
  final agentChats = AgentChatRepository(store: config);
  await agentChats.load();
  final agentMemory = AgentMemoryRepository(store: config);
  await agentMemory.load();
  final tradeProposals = TradeProposalRepository(store: config);
  await tradeProposals.load();
  final investInterestProposals =
      InvestInterestProposalRepository(store: config);
  await investInterestProposals.load();
  final agentActivity = AgentActivityRepository(store: config);
  await agentActivity.load();
  final appNotifications = AppNotificationRepository(store: config);
  await appNotifications.load();
  final shellNav = ShellNavigationController();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final marketClient = marketData ?? FakeMarketDataClient.forSymbol('AAPL');
  final equitiesRegistry = EquityDataSourceRegistry([
    EquityDataSourceEntry(
      source: const EquityDataSource(
        id: 'yahoo',
        displayName: 'Yahoo Finance',
      ),
      client: marketClient,
    ),
  ]);
  final crypto = cryptoRegistry ?? CryptoExchangeRegistry(const []);
  const brokerRegistry = BrokerExchangeRegistry.empty;
  final runner = agentRunner ?? fakeGenkitAgentRunner();
  final tradeExecutor = RoutingTradeExecutor(
    cryptoRegistry: crypto,
    brokerRegistry: brokerRegistry,
    dataSources: dataSourceSettings,
    portfolio: portfolio,
    marketData: marketClient,
  );

  late final LlmRuntimeSettings llmRuntime;
  late final AgentAppSettings agentApp;
  late final EnvSecretsRepository envSecrets;
  if (seedLlm) {
    final seeded = await seedLlmStack(config);
    llmRuntime = seeded.llmRuntime;
    agentApp = seeded.appSettings;
    envSecrets = seeded.secrets;
  } else {
    llmRuntime = LlmRuntimeSettings(store: config);
    await llmRuntime.load();
    agentApp = AgentAppSettings(store: config);
    await agentApp.load();
    envSecrets = EnvSecretsRepository(store: config);
    await envSecrets.load();
  }
  agentChats.appSettings = agentApp;

  final llmConnectionStatus = LlmConnectionStatusStore();
  final agentSchedule = AgentScheduleCoordinator(
    agents: agents,
    chats: agentChats,
    marketData: marketClient,
    agentRunner: runner,
    tradeExecutor: tradeExecutor,
    proposals: tradeProposals,
    activity: agentActivity,
    notifications: appNotifications,
    cryptoRegistry: crypto,
    dataSources: dataSourceSettings,
    portfolio: portfolio,
    favorites: favorites,
    secrets: envSecrets,
    llmRuntime: llmRuntime,
    appSettings: agentApp,
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  final appErrors = AppErrorController(navigatorKey: navigatorKey);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserConfigStore>.value(value: config),
        Provider<MarketDataClient>.value(value: marketClient),
        Provider<EquityDataSourceRegistry>.value(value: equitiesRegistry),
        Provider<VenueCatalog>.value(
          value: VenueCatalog.empty(
            cryptoRegistry: crypto,
            brokerRegistry: brokerRegistry,
          ),
        ),
        Provider<CryptoExchangeRegistry>.value(value: crypto),
        Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
        Provider<TradeExecutor>.value(value: tradeExecutor),
        ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
        ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
        ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
        ChangeNotifierProvider<AgentsRepository>.value(value: agents),
        ChangeNotifierProvider<LlmRuntimeSettings>.value(value: llmRuntime),
        ChangeNotifierProvider<LlmConnectionStatusStore>.value(
          value: llmConnectionStatus,
        ),
        ChangeNotifierProvider<AgentAppSettings>.value(value: agentApp),
        ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
        ChangeNotifierProvider<AgentMemoryRepository>.value(value: agentMemory),
        ChangeNotifierProvider<TradeProposalRepository>.value(
          value: tradeProposals,
        ),
        ChangeNotifierProvider<InvestInterestProposalRepository>.value(
          value: investInterestProposals,
        ),
        ChangeNotifierProvider<AgentActivityRepository>.value(
          value: agentActivity,
        ),
        ChangeNotifierProvider<AppNotificationRepository>.value(
          value: appNotifications,
        ),
        Provider<GenkitAgentRunner>.value(value: runner),
        ChangeNotifierProvider<ThemeSettings>.value(value: themeSettings),
        ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
        ChangeNotifierProvider<DataSourceSettings>.value(
          value: dataSourceSettings,
        ),
        ChangeNotifierProvider<AppErrorController>.value(value: appErrors),
        ChangeNotifierProvider<ShellNavigationController>.value(
          value: shellNav,
        ),
        ChangeNotifierProvider<AgentScheduleCoordinator>.value(
          value: agentSchedule,
        ),
      ],
      child: OmniscopeApp(navigatorKey: navigatorKey),
    ),
  );

  return OmniscopeTestAppContext(
    config: config,
    shellNav: shellNav,
    marketData: marketClient,
    portfolio: portfolio,
    agents: agents,
    chats: agentChats,
    secrets: envSecrets,
    llmRuntime: llmRuntime,
    appSettings: agentApp,
    tradeExecutor: tradeExecutor,
  );
}
