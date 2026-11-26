import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_error_controller.dart';
import 'core/app_error_handling.dart';
import 'core/shell_navigation.dart';
import 'data/agents/agent_activity_repository.dart';
import 'data/agents/agent_app_settings.dart';
import 'data/agents/agent_chat_repository.dart';
import 'data/agents/agent_memory_repository.dart';
import 'data/agents/agent_role_catalog.dart';
import 'data/agents/agents_repository.dart';
import 'data/agents/genkit/genkit_agent_runner.dart';
import 'data/agents/invest_interest_proposal_repository.dart';
import 'data/agents/llm_connection_status_store.dart';
import 'data/agents/llm_model_catalog.dart';
import 'data/agents/llm_model_router.dart';
import 'data/agents/llm_runtime_settings.dart';
import 'data/agents/trade_proposal_repository.dart';
import 'data/crypto/crypto_exchange_registry.dart';
import 'data/market/caching_market_data_client.dart';
import 'data/market/equity_data_source.dart';
import 'data/market/exchange_credentials.dart';
import 'data/market/market_data_client.dart';
import 'data/market/routing_market_data_client.dart';
import 'data/market/yahoo_market_data_client.dart';
import 'data/notifications/app_notification_repository.dart';
import 'data/portfolio/portfolio_repository.dart';
import 'data/settings/data_source_settings.dart';
import 'data/settings/display_settings.dart';
import 'data/settings/env_secrets_repository.dart';
import 'data/settings/favorites_repository.dart';
import 'data/settings/theme_settings.dart';
import 'data/settings/user_config_bootstrap.dart';
import 'data/settings/user_config_store.dart';
import 'data/trading/broker_exchange_registry.dart';
import 'data/trading/trade_executor.dart';
import 'data/venues/venue_catalog.dart';
import 'features/agents/agent_schedule_coordinator.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final navigatorKey = GlobalKey<NavigatorState>();
  final appErrors = AppErrorController(navigatorKey: navigatorKey);
  installAppErrorHandling(appErrors);

  final config = UserConfigStore();

  // Config + asset catalogs are independent — load in parallel.
  late final AgentRoleCatalog agentRoles;
  late final LlmModelCatalog llmModels;
  await Future.wait([
    config.load(),
    AgentRoleCatalog.load().then((v) => agentRoles = v),
    LlmModelCatalog.load().then((v) => llmModels = v),
  ]);

  final portfolio = PortfolioRepository(store: config);
  final themeSettings = ThemeSettings(store: config);
  final displaySettings = DisplaySettings(store: config);
  final dataSourceSettings = DataSourceSettings(store: config);
  final favorites = FavoritesRepository(store: config);
  final agents = AgentsRepository(store: config, roleCatalog: agentRoles);
  final llmRuntime = LlmRuntimeSettings(store: config);
  final agentApp = AgentAppSettings(store: config);
  final agentMemory = AgentMemoryRepository(store: config);
  final tradeProposals = TradeProposalRepository(store: config);
  final investInterestProposals =
      InvestInterestProposalRepository(store: config);
  final agentActivity = AgentActivityRepository(store: config);
  final appNotifications = AppNotificationRepository(store: config);

  // Slice loads are in-memory after config — parallelize freely.
  await Future.wait([
    portfolio.load(),
    themeSettings.load(),
    displaySettings.load(),
    dataSourceSettings.load(),
    favorites.load(),
    agents.load(roleCatalog: agentRoles),
    llmRuntime.load(),
    agentApp.load(),
    agentMemory.load(),
    tradeProposals.load(),
    investInterestProposals.load(),
    agentActivity.load(),
    appNotifications.load(),
  ]);

  final agentChats = AgentChatRepository(
    store: config,
    appSettings: agentApp,
  );
  await agentChats.load();
  await UserConfigBootstrap.runChatAndLlmMigrations(
    config: config,
    agents: agents,
    llmRuntime: llmRuntime,
    agentApp: agentApp,
    chats: agentChats,
    llmModels: llmModels,
  );

  final agentRunner = GenkitAgentRunner();
  final llmConnectionStatus = LlmConnectionStatusStore();

  ExchangeCredentialsConfig.defaultExchangeIds =
      VenueCatalog.knownCredentialVenueIds;

  late final VenueCatalog venues;
  final envSecrets = EnvSecretsRepository(
    store: config,
    onExchangeCredentialsChanged: (exchangeId, credentials) {
      venues.applyCredentials(exchangeId, credentials);
    },
  );
  await envSecrets.load();

  void syncConfigureAgentsReminder() {
    appNotifications.setConfigureAgentsNeeded(
      !LlmModelRouter.hasAnyEndpoint(
        runtime: llmRuntime,
        keys: envSecrets.llmKeys,
      ),
    );
  }

  envSecrets.addListener(syncConfigureAgentsReminder);
  llmRuntime.addListener(syncConfigureAgentsReminder);
  syncConfigureAgentsReminder();

  final equitiesRegistry = EquityDataSourceRegistry([
    EquityDataSourceEntry(
      source: YahooMarketDataClient.meta,
      client: YahooMarketDataClient(),
    ),
  ]);

  venues = VenueCatalog.build(
    credentialsFor: envSecrets.exchangeCredentialsFor,
  );
  final cryptoRegistry = venues.cryptoRegistry;
  final brokerRegistry = venues.brokerRegistry;

  final MarketDataClient marketData = CachingMarketDataClient(
    RoutingMarketDataClient(
      equitiesRegistry: equitiesRegistry,
      cryptoRegistry: cryptoRegistry,
      dataSources: dataSourceSettings,
    ),
  );

  final TradeExecutor tradeExecutor = RoutingTradeExecutor(
    cryptoRegistry: cryptoRegistry,
    brokerRegistry: brokerRegistry,
    dataSources: dataSourceSettings,
    portfolio: portfolio,
    marketData: marketData,
  );

  final agentSchedule = AgentScheduleCoordinator(
    agents: agents,
    chats: agentChats,
    marketData: marketData,
    agentRunner: agentRunner,
    tradeExecutor: tradeExecutor,
    proposals: tradeProposals,
    activity: agentActivity,
    notifications: appNotifications,
    cryptoRegistry: cryptoRegistry,
    dataSources: dataSourceSettings,
    portfolio: portfolio,
    favorites: favorites,
    secrets: envSecrets,
    llmRuntime: llmRuntime,
    appSettings: agentApp,
    agentMemory: agentMemory,
    investInterestProposals: investInterestProposals,
  );

  FlutterNativeSplash.remove();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserConfigStore>.value(value: config),
        Provider<MarketDataClient>.value(value: marketData),
        Provider<EquityDataSourceRegistry>.value(value: equitiesRegistry),
        Provider<VenueCatalog>.value(value: venues),
        Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
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
        Provider<GenkitAgentRunner>.value(value: agentRunner),
        ChangeNotifierProvider<ThemeSettings>.value(value: themeSettings),
        ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
        ChangeNotifierProvider<DataSourceSettings>.value(
          value: dataSourceSettings,
        ),
        ChangeNotifierProvider<AppErrorController>.value(value: appErrors),
        ChangeNotifierProvider<ShellNavigationController>(
          create: (_) => ShellNavigationController(),
        ),
        ChangeNotifierProvider<AgentScheduleCoordinator>.value(
          value: agentSchedule,
        ),
      ],
      child: OmniscopeApp(navigatorKey: navigatorKey),
    ),
  );
}
