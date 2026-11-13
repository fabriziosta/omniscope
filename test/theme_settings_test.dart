import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/settings/theme_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to system and persists selection', () async {
    final store = await memoryConfig();
    final settings = ThemeSettings(store: store);
    await settings.load();
    expect(settings.mode, ThemeMode.system);

    await settings.setMode(ThemeMode.dark);
    expect(settings.mode, ThemeMode.dark);

    final again = ThemeSettings(store: store);
    await again.load();
    expect(again.mode, ThemeMode.dark);
  });

  test('migrates light from legacy prefs', () async {
    final store = await memoryConfig(initialPrefs: {
      UserConfigKeys.legacyTheme: 'light',
    });
    final settings = ThemeSettings(store: store);
    await settings.load();
    expect(settings.mode, ThemeMode.light);
  });
}
