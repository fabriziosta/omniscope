import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'nav_back_button.dart';

/// Back | centered title | optional trailing action for pushed subscreens.
class SubscreenAppBar extends StatelessWidget {
  const SubscreenAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.backLabel = 'Back',
    this.endPadding = 12,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final String backLabel;

  /// Right padding when [trailing] is present (Refresh / Clear).
  final double endPadding;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, endPadding, 0),
      child: Row(
        children: [
          NavBackButton(
            label: backLabel,
            onPressed: onBack ?? () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.h4,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null)
            trailing!
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}
