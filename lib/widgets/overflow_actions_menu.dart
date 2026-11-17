import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_tooltip.dart';

/// Default width under which [RowActionCluster] collapses inline icons.
const double kRowActionsCollapseWidth = 480;

/// Fixed popover width — [ShadPopover] overlays pass unbounded width, so flex
/// children (and `width: double.infinity` on [ShadButton]) must not be used.
const double kOverflowMenuWidth = 220;

/// One entry in an [OverflowActionsMenu] / collapsed [RowActionCluster].
class OverflowAction {
  const OverflowAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// When true, icon/label use primary (e.g. favorited / marked).
  final bool active;
}

/// 44×44 ⋯ trigger with a [ShadPopover] list of actions (brand tokens only).
class OverflowActionsMenu extends StatefulWidget {
  const OverflowActionsMenu({
    super.key,
    required this.actions,
    this.tooltip = 'More actions',
  });

  final List<OverflowAction> actions;
  final String tooltip;

  @override
  State<OverflowActionsMenu> createState() => _OverflowActionsMenuState();
}

class _OverflowActionsMenuState extends State<OverflowActionsMenu> {
  late final ShadPopoverController _controller = ShadPopoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(OverflowAction action) {
    _controller.hide();
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (widget.actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return ShadPopover(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      popover: (_) => SizedBox(
        width: kOverflowMenuWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in widget.actions)
              ShadButton.ghost(
                width: kOverflowMenuWidth,
                mainAxisAlignment: MainAxisAlignment.start,
                onPressed: () => _run(action),
                leading: Icon(
                  action.icon,
                  size: 16,
                  color: action.active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.mutedForeground,
                ),
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.small.copyWith(
                    color: action.active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
      // Child is already a [ShadButton] — no wrapDetector (avoids nested hover).
      child: AppTooltip(
        message: widget.tooltip,
        child: SizedBox(
          width: 44,
          height: 44,
          child: ShadButton.ghost(
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            onPressed: _controller.toggle,
            child: Icon(
              LucideIcons.ellipsisVertical,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [inlineChildren] when the window is wide enough; otherwise a ⋯ menu.
///
/// Place beside a price/value column. Collapse uses [MediaQuery] width so it
/// tracks phone vs desktop, matching Settings connection-card stacking at 480.
class RowActionCluster extends StatelessWidget {
  const RowActionCluster({
    super.key,
    required this.actions,
    required this.inlineChildren,
    required this.child,
    this.breakpoint = kRowActionsCollapseWidth,
  });

  final List<OverflowAction> actions;
  final List<Widget> inlineChildren;

  /// Typically the price / P&L column (wrap in [Flexible] yourself if needed).
  final Widget child;

  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final collapse = MediaQuery.sizeOf(context).width < breakpoint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (collapse && actions.isNotEmpty)
          OverflowActionsMenu(actions: actions)
        else ...[
          for (final w in inlineChildren) w,
        ],
        // Let the price column take remaining width inside the parent Flexible.
        Flexible(child: child),
      ],
    );
  }
}
