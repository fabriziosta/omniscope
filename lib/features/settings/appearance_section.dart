import '../../core/material_compat.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/formatting.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/theme_settings.dart';
import 'settings_option_tiles.dart';

class AppearanceSectionBody extends StatelessWidget {
  const AppearanceSectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by [SettingsNavSubsection.id].
  final Map<String, GlobalKey>? subsectionKeys;

  static const _themeOptions = <(ThemeMode, String)>[
    (ThemeMode.system, 'System'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  static const _densityOptions = <(ListDensity, String)>[
    (ListDensity.comfortable, 'Comfortable'),
    (ListDensity.compact, 'Compact'),
  ];

  static const _priceOptions = <(PriceFormat, String)>[
    (PriceFormat.full, 'Full'),
    (PriceFormat.compact, 'Compact'),
  ];

  static const _chartOptions = <(ChartRangePreset, String)>[
    (ChartRangePreset.oneMonth, '1M'),
    (ChartRangePreset.threeMonths, '3M'),
    (ChartRangePreset.oneYear, '1Y'),
  ];

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettings>();
    final displaySettings = context.watch<DisplaySettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSubsectionLabel(
          'Brightness',
          key: subsectionKeys?['brightness'],
          description:
              'Light, dark, or follow the device. Works with any color set.',
        ),
        const SizedBox(height: 8),
        SettingsChoiceChips<ThemeMode>(
          options: _themeOptions,
          value: themeSettings.mode,
          onChanged: themeSettings.setMode,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Color set',
          key: subsectionKeys?['colorSet'],
          description:
              'Brand accents for buttons, icons, and chrome. '
              'Gain and loss numbers stay green and red in every set.',
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < BrandColors.all.length; i++) ...[
          if (i > 0) const SizedBox(height: settingsOptionGap),
          _PaletteOptionTile(
            palette: BrandColors.all[i],
            selected: themeSettings.paletteId == BrandColors.all[i].id,
            onTap: () => themeSettings.setPaletteId(BrandColors.all[i].id),
          ),
        ],
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Lists',
          key: subsectionKeys?['lists'],
          description: 'How dense Markets list rows look.',
        ),
        const SizedBox(height: 8),
        SettingsChoiceChips<ListDensity>(
          options: _densityOptions,
          value: displaySettings.listDensity,
          onChanged: displaySettings.setListDensity,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Numbers',
          key: subsectionKeys?['numbers'],
          description:
              'How prices appear in Markets, Portfolio, and Asset detail.',
        ),
        const SizedBox(height: 8),
        SettingsChoiceChips<PriceFormat>(
          options: _priceOptions,
          value: displaySettings.priceFormat,
          onChanged: displaySettings.setPriceFormat,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Charts',
          key: subsectionKeys?['charts'],
          description:
              'Default history range when you open an asset. '
              'You can still change it on the chart.',
        ),
        const SizedBox(height: 8),
        SettingsChoiceChips<ChartRangePreset>(
          options: _chartOptions,
          value: displaySettings.defaultChartRange,
          onChanged: displaySettings.setDefaultChartRange,
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _PaletteSwatches(
                    primary: swatchPrimary,
                    secondary: swatchSecondary,
                    border: swatchBorder,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          palette.label,
                          style: theme.textTheme.p.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          palette.description,
                          style: theme.textTheme.small.copyWith(
                            color: selected
                                ? theme.colorScheme.secondaryForeground
                                    .withValues(alpha: 0.8)
                                : theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      LucideIcons.check,
                      size: 16,
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
      width: 46,
      height: 22,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 1,
            child: _Dot(color: primary, outline: theme.colorScheme.border),
          ),
          Positioned(
            left: 12,
            top: 1,
            child: _Dot(color: secondary, outline: border),
          ),
          Positioned(
            left: 24,
            top: 1,
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
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outline),
      ),
    );
  }
}
