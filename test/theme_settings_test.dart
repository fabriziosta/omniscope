import 'package:omniscope/core/material_compat.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
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
    expect(settings.paletteId, BrandColors.defaultPaletteId);

    await settings.setMode(ThemeMode.dark);
    expect(settings.mode, ThemeMode.dark);

    final again = ThemeSettings(store: store);
    await again.load();
    expect(again.mode, ThemeMode.dark);
    expect(again.paletteId, BrandColors.defaultPaletteId);
  });

  test('persists color palette independently of brightness', () async {
    final store = await memoryConfig();
    final settings = ThemeSettings(store: store);
    await settings.load();

    await settings.setPaletteId('ocean');
    await settings.setMode(ThemeMode.light);
    expect(settings.paletteId, 'ocean');
    expect(settings.mode, ThemeMode.light);
    expect(settings.palette.label, 'Ocean');

    final again = ThemeSettings(store: store);
    await again.load();
    expect(again.paletteId, 'ocean');
    expect(again.mode, ThemeMode.light);

    await again.setMode(ThemeMode.dark);
    expect(again.paletteId, 'ocean');
  });

  test('unknown palette id falls back to teal', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.theme, {
      'mode': 'system',
      'palette': 'not-a-real-palette',
    });
    final settings = ThemeSettings(store: store);
    await settings.load();
    expect(settings.paletteId, 'teal');
  });

  test('migrates legacy bare mode string', () async {
    final store = await memoryConfig();
    await store.setSlice(UserConfigKeys.theme, 'dark');
    final settings = ThemeSettings(store: store);
    await settings.load();
    expect(settings.mode, ThemeMode.dark);
    expect(settings.paletteId, BrandColors.defaultPaletteId);
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
