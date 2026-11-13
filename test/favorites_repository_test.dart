import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toggles market and crypto favorites and persists', () async {
    final store = await memoryConfig();
    final repo = FavoritesRepository(store: store);
    await repo.load();

    expect(repo.marketSymbols, isEmpty);
    await repo.toggleMarketFavorite('AAPL');
    await repo.toggleMarketFavorite('SPY');
    expect(repo.isMarketFavorite('AAPL'), isTrue);
    expect(repo.marketSymbols, ['AAPL', 'SPY']);

    await repo.toggleCryptoFavorite('crypto_com', 'BTC_USD');
    expect(repo.isCryptoFavorite('crypto_com', 'BTC_USD'), isTrue);

    await repo.toggleMarketFavorite('AAPL');
    expect(repo.isMarketFavorite('AAPL'), isFalse);
    expect(repo.marketSymbols, ['SPY']);

    final again = FavoritesRepository(store: store);
    await again.load();
    expect(again.marketSymbols, ['SPY']);
    expect(again.cryptoSymbolsFor('crypto_com'), ['BTC_USD']);

    final slice = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(slice['markets'], ['SPY']);
  });

  test('clearAll wipes favorites', () async {
    final store = await memoryConfig();
    final repo = FavoritesRepository(store: store);
    await repo.load();
    await repo.toggleMarketFavorite('MSFT');
    await repo.toggleCryptoFavorite('crypto_com', 'ETH_USD');
    await repo.clearAll();
    expect(repo.marketSymbols, isEmpty);
    expect(repo.cryptoSymbolsFor('crypto_com'), isEmpty);
  });
}
