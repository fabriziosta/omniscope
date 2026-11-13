import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A brand color set with light and dark variants.
///
/// Theme mode (light / dark / system) stays independent — pick a palette once,
/// then switch brightness freely.
class BrandPalette {
  const BrandPalette({
    required this.id,
    required this.label,
    required this.description,
    required this.primaryLight,
    required this.primaryForegroundLight,
    required this.primaryDark,
    required this.primaryForegroundDark,
    required this.secondaryLight,
    required this.secondaryForegroundLight,
    required this.secondaryDark,
    required this.secondaryForegroundDark,
    required this.borderLight,
    required this.borderDark,
    required this.selectionLight,
    required this.selectionDark,
  });

  final String id;
  final String label;
  final String description;

  final Color primaryLight;
  final Color primaryForegroundLight;
  final Color primaryDark;
  final Color primaryForegroundDark;
  final Color secondaryLight;
  final Color secondaryForegroundLight;
  final Color secondaryDark;
  final Color secondaryForegroundDark;
  final Color borderLight;
  final Color borderDark;
  final Color selectionLight;
  final Color selectionDark;

  Color primary(Brightness brightness) =>
      brightness == Brightness.dark ? primaryDark : primaryLight;

  Color secondary(Brightness brightness) =>
      brightness == Brightness.dark ? secondaryDark : secondaryLight;

  Color border(Brightness brightness) =>
      brightness == Brightness.dark ? borderDark : borderLight;

  ShadColorScheme lightScheme() {
    return const ShadSlateColorScheme.light().copyWith(
      primary: primaryLight,
      primaryForeground: primaryForegroundLight,
      secondary: secondaryLight,
      secondaryForeground: secondaryForegroundLight,
      accent: secondaryLight,
      accentForeground: secondaryForegroundLight,
      destructive: BrandColors.lossLight,
      destructiveForeground: primaryForegroundLight,
      border: borderLight,
      input: borderLight,
      ring: primaryLight,
      selection: selectionLight,
    );
  }

  ShadColorScheme darkScheme() {
    return const ShadSlateColorScheme.dark().copyWith(
      primary: primaryDark,
      primaryForeground: primaryForegroundDark,
      secondary: secondaryDark,
      secondaryForeground: secondaryForegroundDark,
      accent: secondaryDark,
      accentForeground: secondaryForegroundDark,
      destructive: BrandColors.lossDark,
      destructiveForeground: primaryForegroundDark,
      border: borderDark,
      input: borderDark,
      ring: primaryDark,
      selection: selectionDark,
    );
  }
}

/// Canonical Omniscope palette helpers. UI chrome uses the **active**
/// [BrandPalette] (via [ThemeSettings] / [BrandColors.palette]); gain / loss
/// stay fixed for readable P&L.
abstract final class BrandColors {
  /// Default Omniscope teal.
  static const teal = BrandPalette(
    id: 'teal',
    label: 'Teal',
    description: 'Classic Omniscope brand',
    primaryLight: Color(0xFF0F766E),
    primaryForegroundLight: Color(0xFFF0FDFA),
    primaryDark: Color(0xFF2DD4BF),
    primaryForegroundDark: Color(0xFF042F2E),
    secondaryLight: Color(0xFFCCFBF1),
    secondaryForegroundLight: Color(0xFF134E4A),
    secondaryDark: Color(0xFF134E4A),
    secondaryForegroundDark: Color(0xFF99F6E4),
    borderLight: Color(0xFFB7C9C5),
    borderDark: Color(0xFF3A5552),
    selectionLight: Color(0xFF99F6E4),
    selectionDark: Color(0xFF115E59),
  );

  static const ocean = BrandPalette(
    id: 'ocean',
    label: 'Ocean',
    description: 'Cool blue accents',
    primaryLight: Color(0xFF1D4ED8),
    primaryForegroundLight: Color(0xFFEFF6FF),
    primaryDark: Color(0xFF60A5FA),
    primaryForegroundDark: Color(0xFF0B1F3A),
    secondaryLight: Color(0xFFDBEAFE),
    secondaryForegroundLight: Color(0xFF1E3A8A),
    secondaryDark: Color(0xFF1E3A8A),
    secondaryForegroundDark: Color(0xFFBFDBFE),
    borderLight: Color(0xFFB8C7DC),
    borderDark: Color(0xFF3A4F6A),
    selectionLight: Color(0xFF93C5FD),
    selectionDark: Color(0xFF1E40AF),
  );

  static const forest = BrandPalette(
    id: 'forest',
    label: 'Forest',
    description: 'Deep green chrome (P&L colors stay separate)',
    primaryLight: Color(0xFF166534),
    primaryForegroundLight: Color(0xFFF0FDF4),
    primaryDark: Color(0xFF86EFAC),
    primaryForegroundDark: Color(0xFF052E16),
    secondaryLight: Color(0xFFDCFCE7),
    secondaryForegroundLight: Color(0xFF14532D),
    secondaryDark: Color(0xFF14532D),
    secondaryForegroundDark: Color(0xFFBBF7D0),
    borderLight: Color(0xFFB7C9B8),
    borderDark: Color(0xFF3A553F),
    selectionLight: Color(0xFF86EFAC),
    selectionDark: Color(0xFF166534),
  );

  static const slate = BrandPalette(
    id: 'slate',
    label: 'Slate',
    description: 'Neutral blue-gray',
    primaryLight: Color(0xFF334155),
    primaryForegroundLight: Color(0xFFF8FAFC),
    primaryDark: Color(0xFF94A3B8),
    primaryForegroundDark: Color(0xFF0F172A),
    secondaryLight: Color(0xFFE2E8F0),
    secondaryForegroundLight: Color(0xFF1E293B),
    secondaryDark: Color(0xFF1E293B),
    secondaryForegroundDark: Color(0xFFCBD5E1),
    borderLight: Color(0xFFCBD5E1),
    borderDark: Color(0xFF475569),
    selectionLight: Color(0xFFCBD5E1),
    selectionDark: Color(0xFF334155),
  );

  static const amber = BrandPalette(
    id: 'amber',
    label: 'Amber',
    description: 'Warm gold accents',
    primaryLight: Color(0xFFB45309),
    primaryForegroundLight: Color(0xFFFFFBEB),
    primaryDark: Color(0xFFFBBF24),
    primaryForegroundDark: Color(0xFF451A03),
    secondaryLight: Color(0xFFFEF3C7),
    secondaryForegroundLight: Color(0xFF92400E),
    secondaryDark: Color(0xFF78350F),
    secondaryForegroundDark: Color(0xFFFDE68A),
    borderLight: Color(0xFFD6C4A8),
    borderDark: Color(0xFF5C4A32),
    selectionLight: Color(0xFFFCD34D),
    selectionDark: Color(0xFFB45309),
  );

  static const all = <BrandPalette>[teal, ocean, forest, slate, amber];

  static const defaultPaletteId = 'teal';

  static BrandPalette palette([String? id]) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return teal;
    for (final p in all) {
      if (p.id == key) return p;
    }
    return teal;
  }

  // --- Backward-compatible teal aliases (default palette) ---
  static const primaryLight = Color(0xFF0F766E);
  static const primaryForegroundLight = Color(0xFFF0FDFA);
  static const primaryDark = Color(0xFF2DD4BF);
  static const primaryForegroundDark = Color(0xFF042F2E);
  static const secondaryLight = Color(0xFFCCFBF1);
  static const secondaryForegroundLight = Color(0xFF134E4A);
  static const secondaryDark = Color(0xFF134E4A);
  static const secondaryForegroundDark = Color(0xFF99F6E4);
  static const borderLight = Color(0xFFB7C9C5);
  static const borderDark = Color(0xFF3A5552);
  static const selectionLight = Color(0xFF99F6E4);
  static const selectionDark = Color(0xFF115E59);

  // --- Numeric semantics (high contrast; shared across palettes) ---
  static const gainLight = Color(0xFF15803D);
  static const gainDark = Color(0xFF4ADE80);
  static const lossLight = Color(0xFFDC2626);
  static const lossDark = Color(0xFFF87171);

  static Color primary(Brightness brightness, {String? paletteId}) =>
      palette(paletteId).primary(brightness);

  static Color secondary(Brightness brightness, {String? paletteId}) =>
      palette(paletteId).secondary(brightness);

  static Color gain(Brightness brightness) =>
      brightness == Brightness.dark ? gainDark : gainLight;

  static Color loss(Brightness brightness) =>
      brightness == Brightness.dark ? lossDark : lossLight;

  static Color gainOf(BuildContext context) =>
      gain(ShadTheme.of(context).brightness);

  static Color lossOf(BuildContext context) =>
      loss(ShadTheme.of(context).brightness);

  /// Soft brand shadow — active primary at low alpha.
  static Color shadow(Brightness brightness, {String? paletteId}) =>
      primary(brightness, paletteId: paletteId).withValues(alpha: 0.16);

  static Color shadowOf(BuildContext context) =>
      ShadTheme.of(context).colorScheme.primary.withValues(alpha: 0.16);

  static ShadColorScheme lightScheme({String? paletteId}) =>
      palette(paletteId).lightScheme();

  static ShadColorScheme darkScheme({String? paletteId}) =>
      palette(paletteId).darkScheme();
}
