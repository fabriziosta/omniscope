import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
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
        const SettingsSubsectionLabel(
          'Brightness',
          description: 'Light, dark, or follow the device. Works with any color set.',
        ),
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
          'Color set',
          description:
              'Brand accents for buttons, icons, and chrome. '
              'Gain and loss numbers stay green and red in every set.',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < BrandColors.all.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _PaletteOptionTile(
            palette: BrandColors.all[i],
            selected: themeSettings.paletteId == BrandColors.all[i].id,
            onTap: () => themeSettings.setPaletteId(BrandColors.all[i].id),
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
          description:
              'How prices appear in Markets, Crypto, Portfolio, and Asset detail.',
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
          description:
              'Default history range when you open an asset. You can still change it on the chart.',
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

class _PaletteOptionTile extends StatelessWidget {
  const _PaletteOptionTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final BrandPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final swatchPrimary = isDark ? palette.primaryDark : palette.primaryLight;
    final swatchSecondary =
        isDark ? palette.secondaryDark : palette.secondaryLight;
    final swatchBorder = isDark ? palette.borderDark : palette.borderLight;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _PaletteSwatches(
                    primary: swatchPrimary,
                    secondary: swatchSecondary,
                    border: swatchBorder,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          palette.label,
                          style: theme.textTheme.large.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          palette.description,
                          style: theme.textTheme.muted.copyWith(
                            color: selected
                                ? theme.colorScheme.secondaryForeground
                                    .withValues(alpha: 0.8)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      LucideIcons.check,
                      size: 18,
                      color: theme.colorScheme.secondaryForeground,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSwatches extends StatelessWidget {
  const _PaletteSwatches({
    required this.primary,
    required this.secondary,
    required this.border,
  });

  final Color primary;
  final Color secondary;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: 52,
      height: 28,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: _Dot(color: primary, outline: theme.colorScheme.border),
          ),
          Positioned(
            left: 14,
            top: 2,
            child: _Dot(color: secondary, outline: border),
          ),
          Positioned(
            left: 28,
            top: 2,
            child: _Dot(color: border, outline: theme.colorScheme.border),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.outline});

  final Color color;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outline),
      ),
    );
  }
}
