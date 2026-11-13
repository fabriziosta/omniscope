import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/formatting.dart';
import 'package:omniscope/data/settings/display_settings.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to comfortable / full / 1mo and persists JSON', () async {
    final store = await memoryConfig();
    final settings = DisplaySettings(store: store);
    await settings.load();
    expect(settings.listDensity, ListDensity.comfortable);
    expect(settings.isCompact, isFalse);
    expect(settings.priceFormat, PriceFormat.full);
    expect(settings.defaultChartRange, ChartRangePreset.oneMonth);

    await settings.setListDensity(ListDensity.compact);
    await settings.setPriceFormat(PriceFormat.compact);
    await settings.setDefaultChartRange(ChartRangePreset.oneYear);
    expect(settings.listDensity, ListDensity.compact);
    expect(settings.priceFormat, PriceFormat.compact);
    expect(settings.defaultChartRange, ChartRangePreset.oneYear);

    final again = DisplaySettings(store: store);
    await again.load();
    expect(again.listDensity, ListDensity.compact);
    expect(again.priceFormat, PriceFormat.compact);
    expect(again.defaultChartRange, ChartRangePreset.oneYear);
  });

  test('migrates legacy comfortable string from prefs', () async {
    final store = await memoryConfig(initialPrefs: {
      UserConfigKeys.legacyDisplay: 'comfortable',
    });
    final settings = DisplaySettings(store: store);
    await settings.load();
    expect(settings.listDensity, ListDensity.comfortable);
    expect(settings.priceFormat, PriceFormat.full);
    expect(settings.defaultChartRange, ChartRangePreset.oneMonth);
  });

  test('migrates JSON display prefs', () async {
    final store = await memoryConfig(initialPrefs: {
      UserConfigKeys.legacyDisplay:
          '{"listDensity":"compact","priceFormat":"compact","defaultChartRange":"3mo"}',
    });
    final settings = DisplaySettings(store: store);
    await settings.load();
    expect(settings.listDensity, ListDensity.compact);
    expect(settings.priceFormat, PriceFormat.compact);
    expect(settings.defaultChartRange, ChartRangePreset.threeMonths);
  });
}
