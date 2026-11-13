import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/agents/agent_launch.dart';
import '../features/agents/agent_launch_actions.dart';
import 'app_tooltip.dart';

/// Compact CTA that launches an in-app agent run for [symbol] / [exchangeId].
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

  Future<void> _onPressed(BuildContext context) {
    return AgentLaunchActions.launch(
      context,
      intent: intent,
      symbol: symbol,
      exchangeId: exchangeId,
      side: side,
      quantity: quantity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = label ?? intent.ctaLabel;
    if (iconOnly) {
      // Keep a hard 44×44 box so dense quote rows do not overflow when
      // ShadButton padding would otherwise grow past the allocated slot.
      return AppTooltip(
        message: text,
        child: SizedBox(
          width: 44,
          height: 44,
          child: ShadButton.ghost(
            size: size,
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            onPressed: () => _onPressed(context),
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
        onPressed: () => _onPressed(context),
        child: Text(text),
      );
    }
    return ShadButton.secondary(
      size: size,
      onPressed: () => _onPressed(context),
      child: Text(text),
    );
  }
}
