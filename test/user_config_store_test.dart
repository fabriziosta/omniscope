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
    expect(favorites.symbols, ['AAPL', 'BTC_USD']);
  });

  test('exportJson is valid JSON with version', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.theme, 'system');
    final decoded = jsonDecode(store.exportJson()) as Map<String, dynamic>;
    expect(decoded['version'], UserConfigKeys.currentVersion);
    expect(decoded['theme'], 'system');
  });

  test('new config is seeded with all default slices', () async {
    final store = await memoryConfig();
    final doc = store.document;
    expect(doc[UserConfigKeys.version], UserConfigKeys.currentVersion);
    expect(doc[UserConfigKeys.theme], isA<Map>());
    expect(doc[UserConfigKeys.display], isA<Map>());
    expect(doc[UserConfigKeys.dataSources], isA<Map>());
    expect(doc[UserConfigKeys.secrets], isA<Map>());
    expect(doc[UserConfigKeys.agents], isA<Map>());
    expect(doc[UserConfigKeys.llmRuntime], isA<Map>());
    expect(doc[UserConfigKeys.agentApp], isA<Map>());
    expect(doc[UserConfigKeys.agentChats], isA<Map>());
    expect(doc[UserConfigKeys.agentMemory], isA<Map>());
    expect(doc[UserConfigKeys.tradeProposals], isA<Map>());
    expect(doc[UserConfigKeys.investInterestProposals], isA<Map>());
    expect(doc[UserConfigKeys.agentActivity], isA<Map>());
    expect(doc[UserConfigKeys.notifications], isA<Map>());
    expect(doc[UserConfigKeys.paperPortfolio], isA<Map>());
    expect(doc[UserConfigKeys.favorites], isA<Map>());
    expect(doc[UserConfigKeys.mandate], isA<Map>());

    final display = doc[UserConfigKeys.display] as Map;
    expect(display['listDensity'], 'compact');
    expect(display['priceFormat'], 'full');
    expect(display['defaultChartRange'], '1mo');

    final mandate = doc[UserConfigKeys.mandate] as Map;
    expect(mandate['goal'], 'learn');
    expect(mandate['maxSymbolCount'], 20);
  });

  test('missing fields are backfilled without wiping user values', () async {
    final store = await memoryConfig();
    await store.importJson(jsonEncode({
      'version': 1,
      'theme': {'mode': 'dark'},
      'display': {'listDensity': 'compact'},
      'favorites': {
        'symbols': ['AAPL'],
      },
    }));

    final theme = store.getSlice(UserConfigKeys.theme) as Map;
    expect(theme['mode'], 'dark');
    expect(theme['palette'], isNotNull);

    final display = store.getSlice(UserConfigKeys.display) as Map;
    expect(display['listDensity'], 'compact');
    expect(display['priceFormat'], 'full');
    expect(display['defaultChartRange'], '1mo');

    final favorites = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(favorites['symbols'], ['AAPL']);
    expect(favorites['investInterest'], isA<List>());

    expect(store.getSlice(UserConfigKeys.mandate), isA<Map>());
    expect(store.getSlice(UserConfigKeys.agentApp), isA<Map>());
  });

  test('memoryOnly store does not require filesystem', () async {
    final store = UserConfigStore(memoryOnly: true);
    SharedPreferences.setMockInitialValues({});
    await store.load();
    expect(store.isReady, isTrue);
    expect(store.usesFilesystem, isFalse);
    expect(store.effectivePath, isNull);
  });

  test('invalid enum values are overwritten with defaults', () async {
    final store = await memoryConfig();
    await store.importJson(jsonEncode({
      'version': 1,
      'theme': {'mode': 'neon', 'palette': 'hotpink'},
      'display': {
        'listDensity': 'huge',
        'priceFormat': 'scientific',
        'defaultChartRange': '99y',
      },
      'mandate': {
        'goal': 'yolo',
        'horizon': 'forever',
        'universe': 'nft',
        'cadencePreference': 'everySecond',
      },
      'agentApp': {
        'scheduleInterval': 'never',
        'answerMood': 'screaming',
      },
      'favorites': {
        'symbols': ['AAPL'],
      },
    }));

    final theme = store.getSlice(UserConfigKeys.theme) as Map;
    expect(theme['mode'], 'system');
    expect(theme['palette'], 'teal');

    final display = store.getSlice(UserConfigKeys.display) as Map;
    expect(display['listDensity'], 'compact');
    expect(display['priceFormat'], 'full');
    expect(display['defaultChartRange'], '1mo');

    final mandate = store.getSlice(UserConfigKeys.mandate) as Map;
    expect(mandate['goal'], 'learn');
    expect(mandate['horizon'], 'medium');
    expect(mandate['universe'], 'both');
    expect(mandate['cadencePreference'], 'hour1');

    final agentApp = store.getSlice(UserConfigKeys.agentApp) as Map;
    expect(agentApp['scheduleInterval'], 'hour1');
    expect(agentApp['answerMood'], 'plain');

    // Valid user data must survive sanitize.
    final favorites = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(favorites['symbols'], ['AAPL']);
  });

  test('wrong-typed config values are overwritten with defaults', () async {
    final store = await memoryConfig();
    await store.importJson(jsonEncode({
      'version': 1,
      'theme': {'mode': 1, 'palette': true},
      'display': {
        'listDensity': false,
        'priceFormat': 3,
        'defaultChartRange': ['1mo'],
      },
      'agentApp': {
        'autopilotEnabled': 'yes',
        'scheduleSymbols': 'AAPL',
      },
      'paperPortfolio': {
        'cash': 'lots',
        'holdings': 'none',
        'startingCash': 'tenk',
      },
      'favorites': {
        'symbols': 'AAPL',
      },
    }));

    final theme = store.getSlice(UserConfigKeys.theme) as Map;
    expect(theme['mode'], 'system');
    expect(theme['palette'], 'teal');

    final display = store.getSlice(UserConfigKeys.display) as Map;
    expect(display['listDensity'], 'compact');
    expect(display['priceFormat'], 'full');
    expect(display['defaultChartRange'], '1mo');

    final agentApp = store.getSlice(UserConfigKeys.agentApp) as Map;
    expect(agentApp['autopilotEnabled'], false);
    expect(agentApp['scheduleSymbols'], isA<List>());

    final paper = store.getSlice(UserConfigKeys.paperPortfolio) as Map;
    expect(paper['cash'], 10000.0);
    expect(paper['holdings'], isA<List>());
    expect(paper['startingCash'], 10000.0);

    final favorites = store.getSlice(UserConfigKeys.favorites) as Map;
    expect(favorites['symbols'], isA<List>());
  });

  test('valid enum values are preserved', () async {
    final store = await memoryConfig();
    await store.importJson(jsonEncode({
      'version': 1,
      'theme': {'mode': 'dark', 'palette': 'ocean'},
      'display': {
        'listDensity': 'comfortable',
        'priceFormat': 'compact',
        'defaultChartRange': '1y',
      },
      'mandate': {
        'goal': 'grow',
        'horizon': 'long',
        'universe': 'crypto',
        'cadencePreference': 'daily',
      },
    }));

    final theme = store.getSlice(UserConfigKeys.theme) as Map;
    expect(theme['mode'], 'dark');
    expect(theme['palette'], 'ocean');

    final display = store.getSlice(UserConfigKeys.display) as Map;
    expect(display['listDensity'], 'comfortable');
    expect(display['priceFormat'], 'compact');
    expect(display['defaultChartRange'], '1y');

    final mandate = store.getSlice(UserConfigKeys.mandate) as Map;
    expect(mandate['goal'], 'grow');
    expect(mandate['horizon'], 'long');
    expect(mandate['universe'], 'crypto');
    expect(mandate['cadencePreference'], 'daily');
  });
}
