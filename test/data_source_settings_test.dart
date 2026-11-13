import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to all enabled and persists opt-outs', () async {
    final store = await memoryConfig();
    final settings = DataSourceSettings(store: store);
    await settings.load();
    expect(settings.isMarketEnabled('yahoo'), isTrue);
    expect(settings.isCryptoEnabled('crypto_com'), isTrue);

    await settings.setMarketEnabled('yahoo', false);
    await settings.setCryptoEnabled('crypto_com', false);
    expect(settings.isMarketEnabled('yahoo'), isFalse);
    expect(settings.isCryptoEnabled('crypto_com'), isFalse);

    final again = DataSourceSettings(store: store);
    await again.load();
    expect(again.isMarketEnabled('yahoo'), isFalse);
    expect(again.isCryptoEnabled('crypto_com'), isFalse);
    expect(again.isMarketEnabled('finnhub'), isTrue);
  });

  test('migrates disabled lists from legacy prefs', () async {
    final store = await memoryConfig(initialPrefs: {
      UserConfigKeys.legacyDataSources:
          '{"disabledMarkets":["yahoo"],"disabledCrypto":["crypto_com"]}',
    });
    final settings = DataSourceSettings(store: store);
    await settings.load();
    expect(settings.isMarketEnabled('yahoo'), isFalse);
    expect(settings.isCryptoEnabled('crypto_com'), isFalse);
  });

  test('toggling back on clears disabled id', () async {
    final store = await memoryConfig();
    final settings = DataSourceSettings(store: store);
    await settings.load();
    await settings.setMarketEnabled('yahoo', false);
    await settings.setMarketEnabled('yahoo', true);
    expect(settings.isMarketEnabled('yahoo'), isTrue);
    expect(settings.disabledMarketIds, isEmpty);
  });
}
