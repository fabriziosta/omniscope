import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toggles favorites and persists', () async {
    final store = await memoryConfig();
    final repo = FavoritesRepository(store: store);
    await repo.load();

    expect(repo.symbols, isEmpty);
    await repo.toggleFavorite('AAPL');
    await repo.toggleFavorite('SPY');
    await repo.toggleFavorite('BTC_USD');
    expect(repo.isFavorite('AAPL'), isTrue);
    expect(repo.symbols, ['AAPL', 'SPY', 'BTC_USD']);

    await repo.toggleFavorite('AAPL');
    expect(repo.isFavorite('AAPL'), isFalse);
    expect(repo.symbols, ['SPY', 'BTC_USD']);

    final again = FavoritesRepository(store: store);
    await again.load();
    expect(again.symbols, ['SPY', 'BTC_USD']);

    final slice = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(slice['symbols'], ['SPY', 'BTC_USD']);
  });

  test('clearAll wipes favorites', () async {
    final store = await memoryConfig();
    final repo = FavoritesRepository(store: store);
    await repo.load();
    await repo.toggleFavorite('MSFT');
    await repo.toggleFavorite('ETH_USD');
    await repo.clearAll();
    expect(repo.symbols, isEmpty);
  });

  test('reorderFavorites persists', () async {
    final store = await memoryConfig();
    final repo = FavoritesRepository(store: store);
    await repo.load();
    await repo.toggleFavorite('AAPL');
    await repo.toggleFavorite('MSFT');
    await repo.toggleFavorite('SPY');
    // Move index 0 → end (destination after removal).
    await repo.reorderFavorites(0, 2);
    expect(repo.symbols, ['MSFT', 'SPY', 'AAPL']);

    final again = FavoritesRepository(store: store);
    await again.load();
    expect(again.symbols, ['MSFT', 'SPY', 'AAPL']);
  });

  test('migrates legacy markets/crypto slice', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.favorites, {
      'markets': ['AAPL', 'SPY', 'AAPL'],
      'crypto': {
        'crypto_com': ['BTC_USD', 'ETH_USD'],
        'other': ['SOL_USD'],
      },
    });

    final repo = FavoritesRepository(store: store);
    await repo.load();
    expect(repo.symbols, ['AAPL', 'SPY', 'BTC_USD', 'ETH_USD', 'SOL_USD']);

    await repo.toggleFavorite('MSFT');
    final slice = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(slice['symbols'], ['AAPL', 'SPY', 'BTC_USD', 'ETH_USD', 'SOL_USD', 'MSFT']);
    expect(slice.containsKey('markets'), isFalse);
    expect(slice.containsKey('crypto'), isFalse);
  });
}
