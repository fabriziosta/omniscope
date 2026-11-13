import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/theme_settings.dart';
import 'settings_option_tiles.dart';

class AppearanceSectionBody extends StatelessWidget {
  const AppearanceSectionBody({super.key});

  static const _themeOptions = <(ThemeMode, String, String)>[
    (ThemeMode.system, 'System', 'Match the device setting'),
    (ThemeMode.light, 'Light', 'Always use the light theme'),
    (ThemeMode.dark, 'Dark', 'Always use the dark theme'),
  ];

  static const _densityOptions = <(ListDensity, String, String)>[
    (
      ListDensity.comfortable,
      'Comfortable',
      'Larger rows with name and source',
    ),
    (
      ListDensity.compact,
      'Compact',
      'Tighter rows for longer Markets and Crypto lists',
    ),
  ];

  static const _priceOptions = <(PriceFormat, String, String)>[
    (
      PriceFormat.full,
      'Full',
      'Always show full currency amounts',
    ),
    (
      PriceFormat.compact,
      'Compact',
      'Shorten larger prices (for example \$12.35K)',
    ),
  ];

  static const _chartOptions = <(ChartRangePreset, String, String)>[
    (
      ChartRangePreset.oneMonth,
      '1M',
      'One month of daily history when you open an asset',
    ),
    (
      ChartRangePreset.threeMonths,
      '3M',
      'Three months of daily history when you open an asset',
    ),
    (
      ChartRangePreset.oneYear,
      '1Y',
      'One year of daily history when you open an asset',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettings>();
    final displaySettings = context.watch<DisplaySettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSubsectionLabel('Theme'),
        const SizedBox(height: 10),
        for (var i = 0; i < _themeOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: _themeOptions[i].$2,
            subtitle: _themeOptions[i].$3,
            selected: themeSettings.mode == _themeOptions[i].$1,
            onTap: () => themeSettings.setMode(_themeOptions[i].$1),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Lists',
          description: 'How dense Markets and Crypto rows look.',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _densityOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: _densityOptions[i].$2,
            subtitle: _densityOptions[i].$3,
            selected: displaySettings.listDensity == _densityOptions[i].$1,
            onTap: () =>
                displaySettings.setListDensity(_densityOptions[i].$1),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Numbers',
          description: 'How prices appear in Markets, Crypto, Portfolio, and Asset detail.',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _priceOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: _priceOptions[i].$2,
            subtitle: _priceOptions[i].$3,
            selected: displaySettings.priceFormat == _priceOptions[i].$1,
            onTap: () => displaySettings.setPriceFormat(_priceOptions[i].$1),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Charts',
          description: 'Default history range when you open an asset. You can still change it on the chart.',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _chartOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: _chartOptions[i].$2,
            subtitle: _chartOptions[i].$3,
            selected:
                displaySettings.defaultChartRange == _chartOptions[i].$1,
            onTap: () =>
                displaySettings.setDefaultChartRange(_chartOptions[i].$1),
          ),
        ],
      ],
    );
  }
}
