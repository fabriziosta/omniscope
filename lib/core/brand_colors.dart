import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Canonical Omniscope palette. All UI chrome must use these tokens.
///
/// Primary / secondary drive brand (icons, fills, borders, shadows, CTAs).
/// Gain / loss are for numeric P&L only — never reuse primary for up/down.
abstract final class BrandColors {
  // --- Primary (teal) — actions, icons, focus, brand marks ---
  static const primaryLight = Color(0xFF0F766E);
  static const primaryForegroundLight = Color(0xFFF0FDFA);
  static const primaryDark = Color(0xFF2DD4BF);
  static const primaryForegroundDark = Color(0xFF042F2E);

  // --- Secondary (soft teal) — wells, selected nav, soft fills ---
  static const secondaryLight = Color(0xFFCCFBF1);
  static const secondaryForegroundLight = Color(0xFF134E4A);
  static const secondaryDark = Color(0xFF134E4A);
  static const secondaryForegroundDark = Color(0xFF99F6E4);

  // --- Chrome derived from primary/secondary (borders, inputs, selection) ---
  // Quieter slate-teal so card frames don't compete with hierarchy.
  static const borderLight = Color(0xFFB7C9C5);
  static const borderDark = Color(0xFF3A5552);
  static const selectionLight = Color(0xFF99F6E4);
  static const selectionDark = Color(0xFF115E59);

  // --- Numeric semantics (high contrast for easy reading) ---
  static const gainLight = Color(0xFF15803D);
  static const gainDark = Color(0xFF4ADE80);
  static const lossLight = Color(0xFFDC2626);
  static const lossDark = Color(0xFFF87171);

  static Color primary(Brightness brightness) =>
      brightness == Brightness.dark ? primaryDark : primaryLight;

  static Color secondary(Brightness brightness) =>
      brightness == Brightness.dark ? secondaryDark : secondaryLight;

  static Color gain(Brightness brightness) =>
      brightness == Brightness.dark ? gainDark : gainLight;

  static Color loss(Brightness brightness) =>
      brightness == Brightness.dark ? lossDark : lossLight;

  static Color gainOf(BuildContext context) =>
      gain(ShadTheme.of(context).brightness);

  static Color lossOf(BuildContext context) =>
      loss(ShadTheme.of(context).brightness);

  /// Soft brand shadow — primary at low alpha (no freeform grays).
  static Color shadow(Brightness brightness) =>
      primary(brightness).withValues(alpha: 0.16);

  static Color shadowOf(BuildContext context) =>
      shadow(ShadTheme.of(context).brightness);

  /// Slate neutrals + brand primary/secondary overrides for [ShadApp].
  static ShadColorScheme lightScheme() {
    return const ShadSlateColorScheme.light().copyWith(
      primary: primaryLight,
      primaryForeground: primaryForegroundLight,
      secondary: secondaryLight,
      secondaryForeground: secondaryForegroundLight,
      accent: secondaryLight,
      accentForeground: secondaryForegroundLight,
      destructive: lossLight,
      destructiveForeground: primaryForegroundLight,
      border: borderLight,
      input: borderLight,
      ring: primaryLight,
      selection: selectionLight,
    );
  }

  static ShadColorScheme darkScheme() {
    return const ShadSlateColorScheme.dark().copyWith(
      primary: primaryDark,
      primaryForeground: primaryForegroundDark,
      secondary: secondaryDark,
      secondaryForeground: secondaryForegroundDark,
      accent: secondaryDark,
      accentForeground: secondaryForegroundDark,
      destructive: lossDark,
      destructiveForeground: primaryForegroundDark,
      border: borderDark,
      input: borderDark,
      ring: primaryDark,
      selection: selectionDark,
    );
  }
}
