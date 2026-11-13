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

class _PendingLiveCryptoClient
    with FakeCryptoLiveVenue
    implements CryptoExchangeClient {
  @override
  final CryptoExchange exchange = CryptoComExchangeClient.meta;

  @override
  bool get supportsLivePortfolio => true;

  @override
  bool get canFetchPortfolio => false;

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
    throw UnsupportedError('credentials required');
  }

  @override
  bool get supportsLiveTrading => true;

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

  testWidgets('Portfolio suggests exchange credentials when Live is locked', (
    tester,
  ) async {
    final store = await memoryConfig();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final displaySettings = DisplaySettings(store: store);
    await displaySettings.load();
    final envSecrets = EnvSecretsRepository(store: store, syncEnvFile: false);
    await envSecrets.load(additionalBootstrap: const {});
    final shellNav = ShellNavigationController();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
            value: CryptoExchangeRegistry([_PendingLiveCryptoClient()]),
          ),
          Provider<BrokerExchangeRegistry>.value(
            value: BrokerExchangeRegistry.empty,
          ),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
          ChangeNotifierProvider<ShellNavigationController>.value(
            value: shellNav,
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
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(AppCopy.connectLivePortfolioTitle), findsOneWidget);
    expect(find.text(AppCopy.connectLivePortfolioCta), findsOneWidget);
    expect(find.textContaining('Supported now: Crypto.com'), findsOneWidget);

    await tester.tap(find.text(AppCopy.connectLivePortfolioCta));
    await tester.pump();

    expect(shellNav.tabIndex, ShellNavigationController.settingsTabIndex);
    expect(shellNav.takePendingSettingsSectionId(), 'dataSources');
  });
}
