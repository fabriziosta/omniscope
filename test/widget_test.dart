import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/app.dart';
import 'package:omniscope/core/app_error_controller.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/crypto/exchange_portfolio.dart';
import 'package:omniscope/data/market/equity_data_source.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/theme_settings.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/order_models.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/data/venues/venue_catalog.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';
import 'package:omniscope/widgets/nav_back_button.dart';
import 'package:provider/provider.dart';

import 'support/fake_live_venue.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

GenkitAgentRunner _testAgentRunner() {
  return fakeGenkitAgentRunner();
}

String _exchangeFor(String symbol) {
  return switch (symbol) {
    '^GSPC' => 'SNP',
    '^DJI' => 'DJI',
    '^IXIC' => 'Nasdaq GIDS',
    'SPY' || 'QQQ' => 'NYSEArca',
    'AAPL' || 'MSFT' => 'NMS',
    'SAP.DE' => 'XETRA',
    _ => 'Other',
  };
}

FakeMarketDataClient _testMarketData() {
  return FakeMarketDataClient(
    basePrice: 100,
    namePrefix: 'Test ',
    previousClose: 99,
    change: 1,
    changePercent: 0.0101,
    exchangeFor: _exchangeFor,
    dataSource: 'Yahoo Finance',
    dataSourceId: 'yahoo',
    historyBuilder: (_) {
      final now = DateTime.now();
      return [
        Candle(time: now.subtract(const Duration(days: 2)), close: 100),
        Candle(time: now.subtract(const Duration(days: 1)), close: 102),
        Candle(time: now, close: 101),
      ];
    },
  );
}

class _FakeCryptoExchangeClient
    with FakeCryptoLiveVenue
    implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = const CryptoExchange(
    id: 'crypto_com',
    displayName: 'Crypto.com',
    defaultSymbols: ['BTC_USD'],
  );

  @override
  bool get supportsLivePortfolio => false;

  @override
  bool get canFetchPortfolio => false;

  @override
  bool handlesSymbol(String symbol) =>
      CryptoComExchangeClient.meta.defaultSymbols.contains(symbol) ||
      symbol.contains('_');

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    return symbols
        .map(
          (s) => Quote(
            symbol: s,
            name: s.split('_').first,
            price: 50,
            change: 1,
            changePercent: 0.02,
            exchange: exchange.displayName,
            dataSource: exchange.displayName,
            dataSourceId: exchange.id,
          ),
        )
        .toList();
  }

  @override
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    throw UnsupportedError('Fake crypto client has no live portfolio.');
  }

  @override
  bool get supportsLiveTrading => false;

  @override
  bool get canPlaceOrders => false;

  @override
  Future<OrderResult> placeOrder(OrderRequest request) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> cancelOrder(String orderId) async =>
      const OrderResult.fail('not supported');

  @override
  Future<OrderResult> getOrder(String orderId) async =>
      const OrderResult.fail('not supported');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpApp(WidgetTester tester) async {
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
    final tradeProposals = TradeProposalRepository(store: config);
    await tradeProposals.load();
    final agentActivity = AgentActivityRepository(store: config);
    await agentActivity.load();
    final appNotifications = AppNotificationRepository(store: config);
    await appNotifications.load();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final marketClient = _testMarketData();
    final equitiesRegistry = EquityDataSourceRegistry([
      EquityDataSourceEntry(
        source: const EquityDataSource(
          id: 'yahoo',
          displayName: 'Yahoo Finance',
        ),
        client: marketClient,
      ),
    ]);
    final cryptoRegistry = CryptoExchangeRegistry([
      _FakeCryptoExchangeClient(),
    ]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final agentRunner = _testAgentRunner();
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: dataSourceSettings,
      portfolio: portfolio,
      marketData: marketClient,
    );
    final agentSchedule = AgentScheduleCoordinator(
      agents: agents,
      chats: agentChats,
      marketData: marketClient,
      agentRunner: agentRunner,
      tradeExecutor: tradeExecutor,
      proposals: tradeProposals,
      activity: agentActivity,
      notifications: appNotifications,
      cryptoRegistry: cryptoRegistry,
      dataSources: dataSourceSettings,
      portfolio: portfolio,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    final appErrors = AppErrorController(navigatorKey: navigatorKey);

    final envSecrets =
        EnvSecretsRepository(store: config, syncEnvFile: false);
    await envSecrets.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserConfigStore>.value(value: config),
          Provider<MarketDataClient>.value(value: marketClient),
          Provider<EquityDataSourceRegistry>.value(value: equitiesRegistry),
          Provider<VenueCatalog>.value(
            value: VenueCatalog.empty(
              cryptoRegistry: cryptoRegistry,
              brokerRegistry: brokerRegistry,
            ),
          ),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // HomeShell resumes the schedule on first frame; stop it for widget tests.
    agentSchedule.pause();
    addTearDown(agentSchedule.dispose);
  }

  testWidgets('shell tabs: markets, portfolio, activity, agents, settings',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('Markets'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Agents'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Indices'), findsOneWidget);
    expect(find.text('ETFs'), findsOneWidget);
    expect(find.text('Stocks'), findsOneWidget);
    expect(find.text('Crypto.com'), findsOneWidget);
    expect(find.text('Spot pairs'), findsOneWidget);
    expect(find.text('0 symbols'), findsOneWidget);
    expect(
      find.text('${watchlistSymbolsForKind(MarketAssetKind.indices).length} symbols'),
      findsOneWidget,
    );
    expect(
      find.text('${watchlistSymbolsForKind(MarketAssetKind.etfs).length} symbols'),
      findsOneWidget,
    );
    expect(
      find.text('${watchlistSymbolsForKind(MarketAssetKind.stocks).length} symbols'),
      findsOneWidget,
    );

    await tester.tap(find.text('Stocks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // First page of stocks (page size 15); AAPL/MSFT → Nasdaq, rest → Other.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('Nasdaq  ·  2'), findsOneWidget);
    expect(find.text('Other  ·  13'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    // Nested tab navigators keep the shell bottom nav visible on detail pages.
    expect(find.text('Portfolio'), findsWidgets);

    // Narrow phone surface: leave Stocks via in-pane Back to see venue tiles.
    expect(find.text('Crypto.com'), findsNothing);
    await tester.tap(find.byType(NavBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Crypto.com'), findsOneWidget);
    await tester.tap(find.text('Crypto.com'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Quote load is async; wait briefly for the fake client.
    for (var i = 0; i < 10 && find.text('BTC_USD').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('BTC_USD'), findsOneWidget);
    expect(find.text('Spot pairs'), findsWidgets);
    expect(find.text('Markets'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Agents'), findsWidgets);

    await tester.tap(find.text('Activity').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Confirm pending'), findsOneWidget);

    await tester.tap(find.text('Agents').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Market Research & Analysis'), findsOneWidget);
    expect(find.textContaining('LangGraph'), findsNothing);
    final agentsCtx = tester.element(find.text('Market Research & Analysis'));
    final roleTitles = agentsCtx
        .read<AgentsRepository>()
        .availableRoles
        .map((r) => r.title)
        .toList();
    expect(roleTitles, contains('Intraday Execution & Risk Control'));
    expect(roleTitles, isNot(contains('Hedge Fund Desk')));
    // Lower roles may sit below the phone viewport — scroll the Roles list.
    final rolesScrollable = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.text('Intraday Execution & Risk Control'),
      300,
      scrollable: rolesScrollable.last,
    );
    await tester.pump();
    expect(find.text('Intraday Execution & Risk Control'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Narrow: section list first (sidebar anchors).
    expect(find.text('About'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.text('Connections'), findsOneWidget);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Lists'), findsOneWidget);
    expect(find.text('Comfortable'), findsOneWidget);
    expect(find.text('Compact'), findsWidgets);
    expect(find.text('Numbers'), findsOneWidget);
    expect(find.text('Charts'), findsOneWidget);
    // Other sections are unloaded while Appearance is open.
    expect(find.text('Market providers'), findsNothing);

    await tester.tap(find.byType(NavBackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data sources'));
    await tester.pumpAndSettle();
    expect(find.text('Market providers'), findsOneWidget);
    expect(find.text('Crypto venues'), findsOneWidget);
    expect(find.text('Yahoo Finance'), findsWidgets);
    expect(find.text('Crypto.com'), findsWidgets);
    expect(find.text('Credentials'), findsOneWidget);
    expect(find.text('System'), findsNothing);

    await tester.tap(find.byType(NavBackButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connections'));
    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    expect(find.text('LLM API keys'), findsOneWidget);
    expect(find.text('Nothing connected yet.'), findsOneWidget);

    await tester.tap(find.byType(NavBackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('groups watchlist quotes by kind then exchange', () {
    final groups = groupQuotesByKindAndExchange(const [
      Quote(symbol: 'AAPL', price: 1, exchange: 'NMS'),
      Quote(symbol: 'SAP.DE', price: 1, exchange: 'XETRA'),
      Quote(symbol: 'SPY', price: 1, exchange: 'NYSEArca'),
      Quote(symbol: '^GSPC', price: 1, exchange: 'SNP'),
    ]);

    expect(groups.map((g) => g.kind), [
      MarketAssetKind.indices,
      MarketAssetKind.etfs,
      MarketAssetKind.stocks,
    ]);
    expect(groups[2].exchanges.map((e) => e.exchange), ['Nasdaq', 'Xetra']);
    expect(groups[2].exchanges[0].quotes.single.symbol, 'AAPL');
  });

  test('exchangeDescription explains common venues', () {
    expect(exchangeDescription('NYSE'), contains('New York Stock Exchange'));
    expect(exchangeDescription('Nasdaq'), contains('tech'));
    expect(exchangeDescription('NYSE Arca'), contains('ETF'));
    expect(exchangeDescription('Unknown Venue'), isNull);
  });

  test('markets tab kinds expose curated symbol lists', () {
    expect(marketTabKinds, [
      MarketAssetKind.indices,
      MarketAssetKind.etfs,
      MarketAssetKind.stocks,
    ]);
    final indices = watchlistSymbolsForKind(MarketAssetKind.indices);
    final etfs = watchlistSymbolsForKind(MarketAssetKind.etfs);
    final stocks = watchlistSymbolsForKind(MarketAssetKind.stocks);
    expect(indices, containsAll(['^GSPC', '^DJI', '^IXIC']));
    expect(indices.length, greaterThanOrEqualTo(3));
    expect(etfs, containsAll(['SPY', 'QQQ']));
    expect(etfs.length, greaterThanOrEqualTo(2));
    expect(stocks, containsAll(['AAPL', 'MSFT', 'SAP.DE']));
    expect(stocks.length, greaterThanOrEqualTo(3));
  });
}
