import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/app.dart';
import 'package:omniscope/core/app_error_controller.dart';
import 'package:omniscope/core/app_info.dart';
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
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/crypto/exchange_portfolio.dart';
import 'package:omniscope/data/market/equity_data_source.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/settings/theme_settings.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/order_models.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/data/venues/venue_catalog.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/features/agents/agent_schedule_coordinator.dart';
import 'package:omniscope/widgets/master_detail_shell.dart';
import 'package:provider/provider.dart';

import 'support/agent_test_harness.dart';
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
    final mandate = MandateSettings(store: config);
    await mandate.load();
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
    // Starter prompt chips only render when an LLM key is configured.
    final seeded = await seedLlmStack(
      config,
      lightModelId: 'gpt-test',
      heavyModelId: 'gpt-test',
    );
    final llmRuntime = seeded.llmRuntime;
    final agentApp = seeded.appSettings;
    agentChats.appSettings = agentApp;
    final envSecrets = seeded.secrets;
    final llmConnectionStatus = LlmConnectionStatusStore();
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
              cryptoRegistry: cryptoRegistry,
              brokerRegistry: brokerRegistry,
            ),
          ),
          Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
          Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
          Provider<TradeExecutor>.value(value: tradeExecutor),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
          ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
          ChangeNotifierProvider<MandateSettings>.value(value: mandate),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<LlmRuntimeSettings>.value(value: llmRuntime),
          ChangeNotifierProvider<LlmConnectionStatusStore>.value(
            value: llmConnectionStatus,
          ),
          ChangeNotifierProvider<AgentAppSettings>.value(value: agentApp),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<AgentMemoryRepository>.value(
            value: agentMemory,
          ),
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
    // Content-first: Indices pane is open; switching to Markets auto-opens nav.
    await tester.pumpAndSettle();
    expect(find.text('Indices'), findsWidgets);
    expect(find.byType(MasterDetailMenuButton), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Invest interest'), findsOneWidget);
    expect(find.text('ETFs'), findsOneWidget);
    expect(find.text('Stocks'), findsOneWidget);
    expect(find.text('Crypto.com'), findsOneWidget);
    expect(find.text('0 symbols'), findsNWidgets(2));
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
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    // First page of stocks (page size 15); AAPL/MSFT → Nasdaq, rest → Other.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('Nasdaq  ·  2'), findsOneWidget);
    expect(find.text('Other  ·  13'), findsOneWidget);
    // Load-more control may sit below the fold on a phone surface.
    await tester.scrollUntilVisible(
      find.textContaining('Showing'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsOneWidget);
    // Nested tab navigators keep the shell bottom nav visible on detail pages.
    expect(find.text('Portfolio'), findsWidgets);

    // Open menu again to reach Crypto.com.
    expect(find.text('Crypto.com'), findsNothing);
    tester
        .widget<MasterDetailMenuButton>(find.byType(MasterDetailMenuButton))
        .onPressed();
    await tester.pumpAndSettle();
    expect(find.text('Crypto.com'), findsOneWidget);
    await tester.tap(find.text('Crypto.com'));
    await tester.pumpAndSettle();
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
    expect(find.text('History'), findsWidgets);
    expect(
      find.textContaining('No agent operations yet'),
      findsOneWidget,
    );

    await tester.tap(find.text('Agents').last);
    await tester.pumpAndSettle();
    expect(find.text('New chat'), findsOneWidget);
    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Market research'), findsOneWidget);
    expect(find.textContaining('LangGraph'), findsNothing);
    final agentsCtx = tester.element(find.text('Market research'));
    final roleTitles = agentsCtx
        .read<AgentsRepository>()
        .availableRoles
        .map((r) => r.title)
        .toList();
    expect(roleTitles, contains('Intraday Execution & Risk Control'));
    expect(roleTitles, isNot(contains('Hedge Fund Desk')));
    // Starter tiles show short labels; the full prompt is drafted on tap.
    final tradeStarter = find.text('Trade check');
    await tester.scrollUntilVisible(
      tradeStarter,
      120,
      scrollable: find
          .descendant(
            of: find.byType(AgentChatScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tradeStarter, findsOneWidget);
    await tester.tap(tradeStarter);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Trade check for'),
      findsOneWidget,
    );

    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Content-first: Appearance is the default section (expanded in sidebar).
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // Subsection titles appear in the expanded sidebar and the body.
    expect(find.text('Lists'), findsWidgets);
    expect(find.text('Comfortable'), findsOneWidget);
    expect(find.text('Compact'), findsWidgets);
    expect(find.text('Numbers'), findsWidgets);
    expect(find.text('Charts'), findsWidgets);
    expect(find.text('Market providers'), findsNothing);

    // Switching to Settings auto-opens the nav drawer — do not toggle the
    // burger here (that would close it). Wait for the open animation.
    await tester.pumpAndSettle();
    expect(find.text('v${AppInfo.version}'), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Brightness'), findsWidgets);

    // Header tap selects the section and expands subsections; nav stays open.
    await tester.tap(find.text('Data sources'));
    await tester.pumpAndSettle();
    expect(find.text('Market providers'), findsWidgets);
    expect(find.text('Crypto venues'), findsWidgets);
    expect(find.text('Yahoo Finance'), findsWidgets);
    expect(find.text('Crypto.com'), findsWidgets);
    expect(find.text('Credentials'), findsWidgets);
    expect(find.text('System'), findsNothing);

    // Subsection tap (sidebar row) scrolls into the body and closes the nav.
    final settingsNav = find.byType(MasterDetailNavList);
    final settingsNavScrollable = find.descendant(
      of: settingsNav,
      matching: find.byType(Scrollable),
    );
    final marketProvidersNav = find.descendant(
      of: settingsNav,
      matching: find.text('Market providers'),
    );
    await tester.ensureVisible(marketProvidersNav);
    await tester.tap(marketProvidersNav);
    await tester.pumpAndSettle();
    // Nav closed — only the body label remains.
    expect(find.text('Market providers'), findsOneWidget);
    expect(find.text('Credentials'), findsOneWidget);

    tester
        .widget<MasterDetailMenuButton>(find.byType(MasterDetailMenuButton))
        .onPressed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.descendant(of: settingsNav, matching: find.text('Connections')),
      120,
      scrollable: settingsNavScrollable.first,
    );
    await tester.tap(
      find.descendant(of: settingsNav, matching: find.text('Connections')),
    );
    await tester.pumpAndSettle();
    // Connections expands; label in sidebar + body.
    expect(find.text('LLM API keys & models'), findsWidgets);
    // Seeded OpenAI key from pumpApp — Connections should show configured state.
    expect(find.textContaining('ChatGPT'), findsWidgets);

    // Subsection tap closes nav; reopen and return to Appearance.
    await tester.tap(
      find.descendant(
        of: settingsNav,
        matching: find.text('LLM API keys & models'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LLM API keys & models'), findsOneWidget);

    tester
        .widget<MasterDetailMenuButton>(find.byType(MasterDetailMenuButton))
        .onPressed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.descendant(of: settingsNav, matching: find.text('Appearance')),
      -120,
      scrollable: settingsNavScrollable.first,
    );
    await tester.tap(
      find.descendant(of: settingsNav, matching: find.text('Appearance')),
    );
    await tester.pumpAndSettle();
    // Close nav via subsection so Dark chips are tappable.
    await tester.tap(
      find.descendant(of: settingsNav, matching: find.text('Brightness')),
    );
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
