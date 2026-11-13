import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates legacy prefs into one document', () async {
    final store = await memoryConfig(initialPrefs: {
      UserConfigKeys.legacyTheme: 'dark',
      UserConfigKeys.legacySecrets: '{"OMNISCOPE_OPENAI_API_KEY":"sk"}',
      UserConfigKeys.legacyDisplay:
          '{"listDensity":"compact","priceFormat":"full","defaultChartRange":"1y"}',
    });

    expect(store.getSlice(UserConfigKeys.theme), 'dark');
    expect(store.getSlice(UserConfigKeys.secrets), isA<Map>());
    expect(
      (store.getSlice(UserConfigKeys.secrets) as Map)['OMNISCOPE_OPENAI_API_KEY'],
      'sk',
    );
    expect(store.getSlice(UserConfigKeys.display), isA<Map>());

    final prefs = await SharedPreferences.getInstance();
    for (final key in UserConfigKeys.legacyPrefsKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
  });

  test('importJson replaces document', () async {
    final store = await memoryConfig();
    await store.importJson(jsonEncode({
      'version': 1,
      'theme': 'light',
      'favorites': {
        'markets': ['AAPL'],
        'crypto': {
          'crypto_com': ['BTC_USD'],
        },
      },
    }));

    expect(store.getSlice(UserConfigKeys.theme), 'light');
    final favorites = FavoritesRepository(store: store);
    await favorites.load();
    expect(favorites.marketSymbols, ['AAPL']);
    expect(favorites.cryptoSymbolsFor('crypto_com'), ['BTC_USD']);
  });

  test('exportJson is valid JSON with version', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.theme, 'system');
    final decoded = jsonDecode(store.exportJson()) as Map<String, dynamic>;
    expect(decoded['version'], UserConfigKeys.currentVersion);
    expect(decoded['theme'], 'system');
  });

  test('memoryOnly store does not require filesystem', () async {
    final store = UserConfigStore(memoryOnly: true);
    SharedPreferences.setMockInitialValues({});
    await store.load();
    expect(store.isReady, isTrue);
    expect(store.usesFilesystem, isFalse);
    expect(store.effectivePath, isNull);
  });
}
