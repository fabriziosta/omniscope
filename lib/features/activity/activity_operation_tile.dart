import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/trade_proposal.dart';

String activityRelativeTime(DateTime utc) => formatRelativeTime(utc);

class ProposalTile extends StatelessWidget {
  const ProposalTile({
    super.key,
    required this.proposal,
    required this.roleTitle,
    required this.portfolioLabel,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final TradeProposal proposal;
  final String roleTitle;
  final String portfolioLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = activityRelativeTime(proposal.createdAt);
    final titleColor = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final mutedColor =
        selected ? theme.colorScheme.secondaryForeground : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.secondary : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${proposal.side.label} ${proposal.quantity} '
                        '${proposal.symbol}',
                        style: theme.textTheme.p.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$roleTitle · ${proposal.status.dashboardLabel} · '
                        '$portfolioLabel · $timeLabel',
                        style: theme.textTheme.muted.copyWith(
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            CleanOperationButton(onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class InvestInterestTile extends StatelessWidget {
  const InvestInterestTile({
    super.key,
    required this.proposal,
    required this.roleTitle,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final InvestInterestProposal proposal;
  final String roleTitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = activityRelativeTime(proposal.createdAt);
    final titleColor = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final mutedColor =
        selected ? theme.colorScheme.secondaryForeground : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.secondary : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proposal.summaryLabel,
                        style: theme.textTheme.p.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$roleTitle · Invest interest · '
                        '${proposal.status.dashboardLabel} · $timeLabel',
                        style: theme.textTheme.muted.copyWith(
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            CleanOperationButton(onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

/// Compact trash control for removing an operation from Activity.
class CleanOperationButton extends StatelessWidget {
  const CleanOperationButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      width: 44,
      height: 44,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Icon(
        LucideIcons.trash2,
        size: 16,
        color: theme.colorScheme.destructive,
      ),
    );
  }
}
