import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared Confirm / Dismiss row for agent proposal cards.
class ProposalConfirmDismissActions extends StatelessWidget {
  const ProposalConfirmDismissActions({
    super.key,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (onConfirm == null && onDismiss == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        if (onDismiss != null)
          Expanded(
            child: SizedBox(
              height: 44,
              child: ShadButton.outline(
                enabled: !busy,
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ),
          ),
        if (onConfirm != null && onDismiss != null) const SizedBox(width: 8),
        if (onConfirm != null)
          Expanded(
            child: SizedBox(
              height: 44,
              child: ShadButton(
                enabled: !busy,
                onPressed: onConfirm,
                child: const Text('Confirm'),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shared chrome for trade / Invest interest proposal cards in chat.
class ProposalCardShell extends StatelessWidget {
  const ProposalCardShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: child,
    );
  }
}
