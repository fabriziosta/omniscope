import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/app_copy.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/crypto/exchange_portfolio.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/order_models.dart';
import 'package:omniscope/features/portfolio/portfolio_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_live_venue.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

class _LiveCryptoClient
    with FakeCryptoLiveVenue
    implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = CryptoComExchangeClient.meta;

  @override
  bool get supportsLivePortfolio => true;

  @override
  bool get canFetchPortfolio => true;

  @override
  bool handlesSymbol(String symbol) => symbol.contains('_');

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => const [];

  @override
  Future<List<String>> browseSymbols() async => exchange.defaultSymbols;

  @override
  Future<ExchangePortfolioSnapshot> fetchPortfolio() async {
    return const ExchangePortfolioSnapshot(
      exchangeId: 'crypto_com',
      exchangeName: 'Crypto.com',
      totalValue: 1250.5,
      availableValue: 1000,
      currency: 'USD',
      balances: [
        ExchangeBalance(
          asset: 'BTC',
          quantity: 0.01,
          marketValue: 650,
          available: 0.01,
        ),
        ExchangeBalance(
          asset: 'USD',
          quantity: 600.5,
          marketValue: 600.5,
          available: 600.5,
        ),
      ],
    );
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

Future<void> _pumpPortfolio(WidgetTester tester) async {
  final store = await memoryConfig();
  final portfolio = PortfolioRepository(store: store);
  await portfolio.load();
  final dataSources = DataSourceSettings(store: store);
  await dataSources.load();
  final displaySettings = DisplaySettings(store: store);
  await displaySettings.load();
  final envSecrets = EnvSecretsRepository(store: store, syncEnvFile: false);
  await envSecrets.load(additionalBootstrap: const {});

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<MarketDataClient>.value(
          value: FakeMarketDataClient(
            basePrice: 100,
            exchange: 'Test',
            emptyHistory: true,
          ),
        ),
        Provider<CryptoExchangeRegistry>.value(
          value: CryptoExchangeRegistry([_LiveCryptoClient()]),
        ),
        Provider<BrokerExchangeRegistry>.value(
          value: BrokerExchangeRegistry.empty,
        ),
        ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
        ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
        ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
        ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
        ChangeNotifierProvider<ShellNavigationController>(
          create: (_) => ShellNavigationController(),
        ),
      ],
      child: ShadApp(
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
        home: const PortfolioScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portfolio master-detail: wide and narrow', (tester) async {
    // Wide: sidebar + Practice content share the viewport.
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    await _pumpPortfolio(tester);

    expect(find.text('Practice'), findsWidgets);
    expect(find.text('Crypto.com'), findsOneWidget);
    expect(find.text('Practice portfolio'), findsOneWidget);

    await tester.tap(find.text('Crypto.com'));
    await tester.pump();

    expect(find.text('Live · Crypto.com'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);

    // Narrow: list first, then one pane at a time.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await _pumpPortfolio(tester);

    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('Crypto.com'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text(AppCopy.connectLivePortfolioTitle), findsNothing);
    expect(find.text('Practice portfolio'), findsNothing);
    expect(find.text('Balances'), findsNothing);

    await tester.tap(find.text('Practice'));
    await tester.pump();

    expect(find.text('Practice portfolio'), findsOneWidget);
    expect(find.textContaining('Fake money for learning'), findsWidgets);

    await tester.tap(find.text('Portfolio'));
    await tester.pump();

    await tester.tap(find.text('Crypto.com'));
    await tester.pump();

    expect(find.text('Live · Crypto.com'), findsOneWidget);
    expect(find.textContaining('Real exchange balances'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    // CTA label + section heading both say "Balances".
    expect(find.text('Balances'), findsNWidgets(2));

    await tester.binding.setSurfaceSize(null);
  });
}
