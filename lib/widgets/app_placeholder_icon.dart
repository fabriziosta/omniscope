import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';

/// Compact brand glyph for the shell header.
///
/// Uses [assets/brand/app_icon.png] (same master as launcher icons).
class AppPlaceholderIcon extends StatelessWidget {
  const AppPlaceholderIcon({super.key, this.size = 24});

  final double size;

  static const assetPath = 'assets/brand/app_icon.png';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final compact = size <= 32;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.border, width: compact ? 1 : 1.5),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: BrandColors.shadowOf(context),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}
