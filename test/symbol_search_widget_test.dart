import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/app_copy.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/widgets/symbol_search.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

class _FakeCryptoClient extends CryptoExchangeClient {
  @override
  final CryptoExchange exchange = const CryptoExchange(
    id: 'crypto_com',
    displayName: 'Crypto.com',
    defaultSymbols: ['BTC_USD'],
  );

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('symbol search lists matches and selects a row', (tester) async {
    final store = await memoryConfig();
    final favorites = FavoritesRepository(store: store);
    await favorites.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final market = FakeMarketDataClient(fixedName: 'Apple Inc.');
    String? selected;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CryptoExchangeRegistry>.value(
            value: CryptoExchangeRegistry([_FakeCryptoClient()]),
          ),
          ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          Provider<MarketDataClient>.value(value: market),
        ],
        child: ShadApp(
          home: Builder(
            builder: (context) {
              return ColoredBox(
                color: ShadTheme.of(context).colorScheme.background,
                child: Center(
                  child: SymbolSearchButton(
                    onSymbolSelected: (symbol) => selected = symbol,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SymbolSearchButton));
    await tester.pumpAndSettle();

    expect(find.text(AppCopy.symbolSearchHint), findsOneWidget);

    // Search field should take focus immediately (desktop caret / mobile keyboard).
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    // Wait for catalog bootstrap + optional name enrichment.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(ShadInput), 'apple');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsWidgets);
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(selected, 'AAPL');
  });
}
