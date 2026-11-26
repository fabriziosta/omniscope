import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/trade_proposal.dart';
import '../../widgets/agent_launch_button.dart';
import 'activity_operation_tile.dart';

class ActivityEventTile extends StatelessWidget {
  const ActivityEventTile({
    super.key,
    required this.event,
    required this.roleTitle,
    this.portfolioLabel,
  });

  final AgentActivityEvent event;
  final String roleTitle;
  final String? portfolioLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = activityRelativeTime(event.createdAt);
    final meta = [
      event.kind.label,
      roleTitle,
      ?portfolioLabel,
      timeLabel,
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta,
              style: theme.textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (event.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(event.summary, style: theme.textTheme.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class InvestInterestDetail extends StatelessWidget {
  const InvestInterestDetail({
    super.key,
    required this.proposal,
    required this.events,
    required this.roleTitle,
    required this.onOpenChat,
    required this.onDelete,
    this.onBack,
  });

  final InvestInterestProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final VoidCallback onOpenChat;
  final VoidCallback onDelete;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final pending =
        proposal.status == InvestInterestProposalStatus.pending;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(proposal.summaryLabel, style: theme.textTheme.h4),
            ),
            CleanOperationButton(onPressed: onDelete),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$roleTitle · Invest interest · ${proposal.status.dashboardLabel}',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 4),
        Text(
          activityRelativeTime(proposal.createdAt),
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
        if (proposal.add.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Add: ${proposal.add.join(', ')}', style: theme.textTheme.p),
        ],
        if (proposal.remove.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Remove: ${proposal.remove.join(', ')}',
            style: theme.textTheme.p,
          ),
        ],
        if (proposal.setSymbols != null) ...[
          const SizedBox(height: 8),
          Text(
            'Set to: ${proposal.setSymbols!.join(', ')}',
            style: theme.textTheme.p,
          ),
        ],
        if (proposal.rationale.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(proposal.rationale, style: theme.textTheme.p),
        ],
        if (proposal.applyError != null) ...[
          const SizedBox(height: 8),
          Text(
            proposal.applyError!,
            style: theme.textTheme.small.copyWith(
              color: BrandColors.lossOf(context),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ShadButton(
            onPressed: onOpenChat,
            child: Text(pending ? 'Open chat to confirm' : 'Open chat'),
          ),
        ),
        const SizedBox(height: 20),
        Text('Timeline', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text('No linked events.', style: theme.textTheme.muted)
        else
          for (final e in events) ...[
            ActivityEventTile(event: e, roleTitle: roleTitle),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class ProposalDetail extends StatelessWidget {
  const ProposalDetail({
    super.key,
    required this.proposal,
    required this.events,
    required this.roleTitle,
    required this.portfolioLabel,
    required this.onOpenChat,
    required this.onDelete,
    this.onBack,
  });

  final TradeProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final String portfolioLabel;
  final VoidCallback onOpenChat;
  final VoidCallback onDelete;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final riskColor = proposal.riskApproved
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);
    final pending = proposal.status == TradeProposalStatus.pending;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
                style: theme.textTheme.h4,
              ),
            ),
            CleanOperationButton(onPressed: onDelete),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$roleTitle · ${proposal.status.dashboardLabel} · $portfolioLabel',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 4),
        Text(
          activityRelativeTime(proposal.createdAt),
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 8),
        Text(
          proposal.riskApproved ? 'Risk approved' : 'Risk veto',
          style: theme.textTheme.small.copyWith(
            color: riskColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (proposal.rationale.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(proposal.rationale, style: theme.textTheme.p),
        ],
        if (proposal.orderId != null) ...[
          const SizedBox(height: 8),
          Text('Order: ${proposal.orderId}', style: theme.textTheme.small),
        ],
        if (proposal.executionError != null) ...[
          const SizedBox(height: 8),
          Text(
            proposal.executionError!,
            style: theme.textTheme.small.copyWith(
              color: BrandColors.lossOf(context),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ShadButton(
            onPressed: onOpenChat,
            child: Text(pending ? 'Open chat to confirm' : 'Open chat'),
          ),
        ),
        if (pending && proposal.symbol.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AgentLaunchButton(
              symbol: proposal.symbol,
              intent: AgentLaunchIntent.tradeCheck,
              exchangeId: proposal.exchangeId == 'practice'
                  ? null
                  : proposal.exchangeId,
              side: proposal.side.name,
              quantity: proposal.quantity > 0 ? proposal.quantity : null,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Timeline', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text('No linked events.', style: theme.textTheme.muted)
        else
          for (final e in events) ...[
            ActivityEventTile(
              event: e,
              roleTitle: roleTitle,
              portfolioLabel: e.exchangeId == null
                  ? null
                  : (e.exchangeId == proposal.exchangeId
                      ? portfolioLabel
                      : e.exchangeId),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}
