import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/agents/agent_launch.dart';
import '../features/agents/agent_launch_actions.dart';
import 'app_tooltip.dart';
import 'overflow_actions_menu.dart';

/// Compact CTA that launches an in-app agent run for [symbol] / [exchangeId].
///
/// When [intent] is [AgentLaunchIntent.investigate] and [showTradeOption] is
/// true (default), opens a popover with Investigate + Trade check.
class AgentLaunchButton extends StatelessWidget {
  const AgentLaunchButton({
    super.key,
    this.symbol,
    required this.intent,
    this.exchangeId,
    this.size = ShadButtonSize.sm,
    this.outline = false,
    this.iconOnly = false,
    this.side,
    this.quantity,
    this.label,
    this.showTradeOption = true,
    this.afterLaunch,
  });

  /// Symbol or asset hint (optional for [AgentLaunchIntent.explainLive]).
  final String? symbol;
  final AgentLaunchIntent intent;

  /// Live exchange id for [AgentLaunchIntent.explainLive].
  final String? exchangeId;
  final ShadButtonSize size;
  final bool outline;
  final bool iconOnly;
  final String? side;
  final double? quantity;
  final String? label;

  /// When [intent] is investigate, offer Trade check as a second menu item.
  final bool showTradeOption;

  /// Called after a launch attempt (e.g. dismiss a search dialog).
  final VoidCallback? afterLaunch;

  bool get _useDualMenu =>
      intent == AgentLaunchIntent.investigate && showTradeOption;

  Future<void> _launch(BuildContext context, AgentLaunchIntent launchIntent) async {
    await AgentLaunchActions.launch(
      context,
      intent: launchIntent,
      symbol: symbol,
      exchangeId: exchangeId,
      side: side,
      quantity: quantity,
    );
    afterLaunch?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_useDualMenu) {
      return _AgentLaunchMenuButton(
        symbol: symbol,
        size: size,
        outline: outline,
        iconOnly: iconOnly,
        label: label ?? intent.ctaLabel,
        onLaunch: (launchIntent) => _launch(context, launchIntent),
      );
    }
    return _AgentLaunchSingleButton(
      label: label ?? intent.ctaLabel,
      size: size,
      outline: outline,
      iconOnly: iconOnly,
      onPressed: () => _launch(context, intent),
    );
  }
}

class _AgentLaunchSingleButton extends StatelessWidget {
  const _AgentLaunchSingleButton({
    required this.label,
    required this.size,
    required this.outline,
    required this.iconOnly,
    required this.onPressed,
  });

  final String label;
  final ShadButtonSize size;
  final bool outline;
  final bool iconOnly;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      // Keep a hard 44×44 box so dense quote rows do not overflow when
      // ShadButton padding would otherwise grow past the allocated slot.
      return AppTooltip(
        message: label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: ShadButton.ghost(
            size: size,
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            child: Icon(
              LucideIcons.sparkles,
              size: 18,
              color: ShadTheme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }
    if (outline) {
      return ShadButton.outline(
        size: size,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return ShadButton.secondary(
      size: size,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _AgentLaunchMenuButton extends StatefulWidget {
  const _AgentLaunchMenuButton({
    required this.symbol,
    required this.size,
    required this.outline,
    required this.iconOnly,
    required this.label,
    required this.onLaunch,
  });

  final String? symbol;
  final ShadButtonSize size;
  final bool outline;
  final bool iconOnly;
  final String label;
  final Future<void> Function(AgentLaunchIntent intent) onLaunch;

  @override
  State<_AgentLaunchMenuButton> createState() => _AgentLaunchMenuButtonState();
}

class _AgentLaunchMenuButtonState extends State<_AgentLaunchMenuButton> {
  late final ShadPopoverController _controller = ShadPopoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(AgentLaunchIntent intent) {
    _controller.hide();
    widget.onLaunch(intent);
  }

  Widget _menuItem({
    required ShadThemeData theme,
    required String label,
    required IconData icon,
    required AgentLaunchIntent intent,
  }) {
    return ShadButton.ghost(
      width: kOverflowMenuWidth,
      mainAxisAlignment: MainAxisAlignment.start,
      onPressed: () => _run(intent),
      leading: Icon(
        icon,
        size: 16,
        color: theme.colorScheme.mutedForeground,
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.foreground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _trigger(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (widget.iconOnly) {
      return AppTooltip(
        message: widget.label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: ShadButton.ghost(
            size: widget.size,
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            onPressed: _controller.toggle,
            child: Icon(
              LucideIcons.sparkles,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }
    if (widget.outline) {
      return ShadButton.outline(
        size: widget.size,
        onPressed: _controller.toggle,
        trailing: Icon(
          LucideIcons.chevronDown,
          size: 14,
          color: theme.colorScheme.primary,
        ),
        child: Text(widget.label),
      );
    }
    return ShadButton.secondary(
      size: widget.size,
      onPressed: _controller.toggle,
      trailing: Icon(
        LucideIcons.chevronDown,
        size: 14,
        color: theme.colorScheme.primaryForeground,
      ),
      child: Text(widget.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadPopover(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      popover: (_) => SizedBox(
        width: kOverflowMenuWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuItem(
              theme: theme,
              label: AgentLaunchIntent.investigate.ctaLabel,
              icon: LucideIcons.sparkles,
              intent: AgentLaunchIntent.investigate,
            ),
            _menuItem(
              theme: theme,
              label: AgentLaunchIntent.tradeCheck.ctaLabel,
              icon: LucideIcons.candlestickChart,
              intent: AgentLaunchIntent.tradeCheck,
            ),
          ],
        ),
      ),
      child: _trigger(context),
    );
  }
}
