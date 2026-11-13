import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_error_controller.dart';
import 'core/app_error_handling.dart';
import 'core/shell_navigation.dart';
import 'data/agents/agent_activity_repository.dart';
import 'data/agents/agent_chat_repository.dart';
import 'data/agents/agent_role_catalog.dart';
import 'data/agents/agents_repository.dart';
import 'data/agents/llm_chat_client.dart';
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
  await config.load();

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

  final tradeProposals = TradeProposalRepository(store: config);
  await tradeProposals.load();

  final agentActivity = AgentActivityRepository(store: config);
  await agentActivity.load();

  final appNotifications = AppNotificationRepository(store: config);
  await appNotifications.load();

  final llmChat = LlmChatClient();

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
    llm: llmChat,
    tradeExecutor: tradeExecutor,
    proposals: tradeProposals,
    activity: agentActivity,
    notifications: appNotifications,
    cryptoRegistry: cryptoRegistry,
    dataSources: dataSourceSettings,
    portfolio: portfolio,
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
        ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
        ChangeNotifierProvider<TradeProposalRepository>.value(
          value: tradeProposals,
        ),
        ChangeNotifierProvider<AgentActivityRepository>.value(
          value: agentActivity,
        ),
        ChangeNotifierProvider<AppNotificationRepository>.value(
          value: appNotifications,
        ),
        Provider<LlmChatClient>.value(value: llmChat),
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
