import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_text.dart';
import 'app_tooltip.dart';

/// Width under which the back control shows the arrow only (label in tooltip).
const double kNavBackIconOnlyWidth = 360;

/// Top-of-screen back control: primary arrow + parent label, ≥44px tap target.
class NavBackButton extends StatelessWidget {
  const NavBackButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final iconOnly = MediaQuery.sizeOf(context).width < kNavBackIconOnlyWidth;

    return AppTooltip(
      message: 'Back to $label',
      wrapDetector: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.arrowLeft,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  if (!iconOnly) ...[
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: AppEllipsisText(
                        label,
                        maxLines: 1,
                        style: theme.textTheme.small.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
