import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/crypto/crypto_exchange.dart';
import 'package:omniscope/data/crypto/crypto_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_links.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/market/symbol_search_index.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

class _FakeCryptoClient extends CryptoExchangeClient {
  _FakeCryptoClient({
    this.browse = const ['BTC_USD', 'ETH_USD', 'SOL_USD'],
  });

  final List<String> browse;

  @override
  late final CryptoExchange exchange = const CryptoExchange(
    id: 'crypto_com',
    displayName: 'Crypto.com',
    defaultSymbols: ['BTC_USD', 'ETH_USD'],
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
  Future<List<String>> browseSymbols() async => browse;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offlineSymbolDisplayName', () {
    test('uses crypto pair labels and wikipedia titles', () {
      expect(offlineSymbolDisplayName('BTC_USD'), 'BTC / USD');
      expect(offlineSymbolDisplayName('AAPL'), 'Apple Inc.');
      expect(wikipediaDisplayName('SOL_USD'), 'Solana');
      expect(offlineSymbolDisplayName('ZZZZ'), isNull);
    });
  });

  group('buildSymbolSearchEntries / filter', () {
    test('unions watchlist, crypto defaults, favorites, and holdings',
        () async {
      final store = await memoryConfig();
      final favorites = FavoritesRepository(store: store);
      await favorites.load();
      await favorites.toggleFavorite('CUSTOM1');

      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      await portfolio.buy(symbol: 'HOLD1', shares: 1, price: 10);

      final crypto = CryptoExchangeRegistry([_FakeCryptoClient()]);
      final entries = buildSymbolSearchEntries(
        cryptoRegistry: crypto,
        favorites: favorites,
        portfolio: portfolio,
      );
      final symbols = entries.map((e) => e.symbol).toSet();

      expect(symbols.contains('AAPL'), isTrue);
      expect(symbols.contains('BTC_USD'), isTrue);
      expect(symbols.contains('CUSTOM1'), isTrue);
      expect(symbols.contains('HOLD1'), isTrue);

      final aapl = entries.firstWhere((e) => e.symbol == 'AAPL');
      expect(aapl.kindLabel, 'Stocks');
      expect(aapl.name, 'Apple Inc.');

      final btc = entries.firstWhere((e) => e.symbol == 'BTC_USD');
      expect(btc.kindLabel, 'Crypto');
      expect(btc.name, 'BTC / USD');
    });

    test('filterSymbolSearchEntries matches symbol and name', () {
      const entries = [
        SymbolSearchEntry(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          kindLabel: 'Stocks',
        ),
        SymbolSearchEntry(
          symbol: 'BTC_USD',
          name: 'BTC / USD',
          kindLabel: 'Crypto',
        ),
        SymbolSearchEntry(
          symbol: 'MSFT',
          name: 'Microsoft',
          kindLabel: 'Stocks',
        ),
      ];

      expect(
        filterSymbolSearchEntries(entries, 'aap').map((e) => e.symbol),
        ['AAPL'],
      );
      expect(
        filterSymbolSearchEntries(entries, 'micro').map((e) => e.symbol),
        ['MSFT'],
      );
      expect(
        filterSymbolSearchEntries(entries, 'btc /').map((e) => e.symbol),
        ['BTC_USD'],
      );
      expect(filterSymbolSearchEntries(entries, '   '), hasLength(3));
      expect(filterSymbolSearchEntries(entries, 'zzz'), isEmpty);
    });

    test('mergeCryptoBrowseSymbols adds live catalog', () async {
      final crypto = CryptoExchangeRegistry([
        _FakeCryptoClient(browse: const ['BTC_USD', 'LINK_USD']),
      ]);
      final merged = await mergeCryptoBrowseSymbols(cryptoRegistry: crypto);
      expect(merged.contains('LINK_USD'), isTrue);
      expect(merged.contains('BTC_USD'), isTrue);
    });

    test('enrichSymbolDisplayNames prefers Quote.name', () async {
      final market = FakeMarketDataClient(namePrefix: 'Live ');
      final names = await enrichSymbolDisplayNames(
        marketData: market,
        symbols: const ['AAPL', 'MSFT'],
      );
      expect(names['AAPL'], 'Live AAPL');
      expect(names['MSFT'], 'Live MSFT');

      final applied = applyDisplayNames(
        const [
          SymbolSearchEntry(symbol: 'AAPL', name: 'Apple Inc.'),
          SymbolSearchEntry(symbol: 'ZZZ', name: 'Keep me'),
        ],
        names,
      );
      expect(applied[0].name, 'Live AAPL');
      expect(applied[1].name, 'Keep me');
    });
  });
}
