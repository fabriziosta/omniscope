import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_text.dart';
import 'master_detail_shell.dart';
import 'nav_back_button.dart';

/// Leading control | title | optional trailing for pushed / embedded screens.
///
/// Prefer [onOpenMenu] when embedded in [MasterDetailShell]; use [showBack] for
/// real Navigator pops (e.g. asset detail).
class SubscreenAppBar extends StatelessWidget {
  const SubscreenAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.backLabel = 'Back',
    this.showBack = true,
    this.onOpenMenu,
    this.endPadding = 12,
    this.titleAlign = TextAlign.center,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final String backLabel;

  /// When true and [onOpenMenu] is null, show Back (Navigator / custom).
  final bool showBack;

  /// When set, show a burger instead of Back (master–detail embedding).
  final VoidCallback? onOpenMenu;

  /// Right padding when [trailing] is present (Refresh / Clear).
  final double endPadding;

  /// Title alignment. Centered titles keep side spacers so the label stays
  /// visually centered; start/left skips them so long titles get more width.
  final TextAlign titleAlign;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final openMenu = onOpenMenu;
    final hasLeading = openMenu != null || showBack;
    final centered = titleAlign == TextAlign.center;

    return Padding(
      padding: EdgeInsets.fromLTRB(hasLeading ? 8 : 16, 8, endPadding, 0),
      child: Row(
        children: [
          if (openMenu != null)
            MasterDetailMenuButton(onPressed: openMenu)
          else if (showBack)
            NavBackButton(
              label: backLabel,
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            )
          else if (centered)
            const SizedBox(width: 64),
          Expanded(
            child: AppEllipsisText(
              title,
              style: theme.textTheme.h4,
              textAlign: titleAlign,
              maxLines: 2,
            ),
          ),
          if (trailing != null)
            trailing!
          else if (centered)
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}
