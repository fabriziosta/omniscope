import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
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
import 'package:omniscope/features/portfolio/portfolio_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/memory_config.dart';

class _FakeMarketDataClient implements MarketDataClient {
  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async => [
        for (final s in symbols)
          Quote(symbol: s, name: s, price: 100, exchange: 'Test'),
      ];
}

class _LiveCryptoClient implements CryptoExchangeClient {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows Practice paper and Live exchange subgroups', (
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

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(value: _FakeMarketDataClient()),
          Provider<CryptoExchangeRegistry>.value(
            value: CryptoExchangeRegistry([_LiveCryptoClient()]),
          ),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          ChangeNotifierProvider<DisplaySettings>.value(value: displaySettings),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: envSecrets),
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

    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Live · Crypto.com'), findsOneWidget);
    expect(find.text('Practice portfolio'), findsOneWidget);
    expect(find.textContaining('Fake money for learning'), findsOneWidget);
    expect(find.textContaining('Real exchange balances'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('Balances'), findsOneWidget);
  });
}
