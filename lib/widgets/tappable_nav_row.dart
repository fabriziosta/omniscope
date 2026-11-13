import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Quiet card row that navigates somewhere — primary chevron signals push.
class TappableNavRow extends StatelessWidget {
  const TappableNavRow({
    super.key,
    required this.onTap,
    required this.leading,
    this.trailing,
    this.compact = false,
  });

  final VoidCallback onTap;
  final Widget leading;
  final Widget? trailing;

  /// Tighter padding and chevron for dense Markets / Crypto lists.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.all(16);

    return ShadCard(
      padding: padding,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Expanded(child: leading),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  // Flexible so icon CTAs + price can shrink on narrow panes
                  // without overflowing the card row.
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing!,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  LucideIcons.chevronRight,
                  color: theme.colorScheme.primary,
                  size: compact ? 16 : 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
