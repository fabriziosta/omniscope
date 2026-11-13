import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_error_controller.dart';
import 'core/app_error_handling.dart';
import 'data/agents/agent_chat_repository.dart';
import 'data/agents/agent_role_catalog.dart';
import 'data/agents/agents_repository.dart';
import 'data/agents/llm_chat_client.dart';
import 'data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'data/crypto/crypto_exchange_registry.dart';
import 'data/market/equity_data_source.dart';
import 'data/market/market_data_client.dart';
import 'data/market/routing_market_data_client.dart';
import 'data/market/yahoo_market_data_client.dart';
import 'data/portfolio/portfolio_repository.dart';
import 'data/settings/data_source_settings.dart';
import 'data/settings/display_settings.dart';
import 'data/settings/env_secrets_repository.dart';
import 'data/settings/favorites_repository.dart';
import 'data/settings/theme_settings.dart';
import 'data/settings/user_config_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final llmChat = LlmChatClient();

  late final CryptoComExchangeClient cryptoCom;
  final envSecrets = EnvSecretsRepository(
    store: config,
    onExchangeCredentialsChanged: (exchangeId, credentials) {
      if (exchangeId == CryptoComExchangeClient.meta.id) {
        cryptoCom.setCredentials(credentials);
      }
    },
  );
  await envSecrets.load();

  final equitiesRegistry = EquityDataSourceRegistry([
    EquityDataSourceEntry(
      source: YahooMarketDataClient.meta,
      client: YahooMarketDataClient(),
    ),
  ]);

  cryptoCom = CryptoComExchangeClient(
    credentials: envSecrets.exchangeCredentialsFor(
      CryptoComExchangeClient.meta.id,
    ),
  );

  final cryptoRegistry = CryptoExchangeRegistry([cryptoCom]);

  final MarketDataClient marketData = RoutingMarketDataClient(
    equitiesRegistry: equitiesRegistry,
    cryptoRegistry: cryptoRegistry,
    dataSources: dataSourceSettings,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserConfigStore>.value(value: config),
        Provider<MarketDataClient>.value(value: marketData),
        Provider<EquityDataSourceRegistry>.value(value: equitiesRegistry),
        Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
        ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
        ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
        ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
        ChangeNotifierProvider<AgentsRepository>.value(value: agents),
        ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
        Provider<LlmChatClient>.value(value: llmChat),
        ChangeNotifierProvider<ThemeSettings>.value(value: themeSettings),
        ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
        ChangeNotifierProvider<DataSourceSettings>.value(
          value: dataSourceSettings,
        ),
        ChangeNotifierProvider<AppErrorController>.value(value: appErrors),
      ],
      child: OmniscopeApp(navigatorKey: navigatorKey),
    ),
  );
}
