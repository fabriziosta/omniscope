import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/proposal_confirm_dismiss_actions.dart';

String agentProposalPortfolioLabel(BuildContext context, String portfolioId) {
  try {
    final venues = context.read<TradeExecutor>().tradableVenues;
    for (final v in venues) {
      if (v.id == portfolioId) return v.displayName;
    }
  } catch (_) {
    // Provider may be absent in isolated tests.
  }
  if (portfolioId == 'practice') return 'Practice';
  return portfolioId;
}

class TradeProposalCard extends StatelessWidget {
  const TradeProposalCard({
    super.key,
    required this.proposal,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final TradeProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final riskColor = proposal.riskApproved
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);

    return ProposalCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
            style: theme.textTheme.large,
          ),
          const SizedBox(height: 4),
          Text(
            'Portfolio: ${agentProposalPortfolioLabel(context, proposal.exchangeId)} · '
            '${proposal.status.label}'
            '${proposal.autopilot ? ' · Autopilot' : ''}',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 6),
          Text(
            proposal.riskApproved ? 'Risk approved' : 'Risk veto',
            style: theme.textTheme.small.copyWith(
              color: riskColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (proposal.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(proposal.rationale, style: theme.textTheme.small),
          ],
          if (proposal.executionError != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.executionError!,
              style: theme.textTheme.small.copyWith(
                color: BrandColors.lossOf(context),
              ),
            ),
          ],
          if (proposal.orderId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Order id: ${proposal.orderId}',
              style: theme.textTheme.small,
            ),
          ],
          if (onConfirm != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            ProposalConfirmDismissActions(
              onConfirm: onConfirm,
              onDismiss: onDismiss,
              busy: busy,
            ),
          ],
        ],
      ),
    );
  }
}

class InvestInterestProposalCard extends StatelessWidget {
  const InvestInterestProposalCard({
    super.key,
    required this.proposal,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final InvestInterestProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ProposalCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(proposal.summaryLabel, style: theme.textTheme.large),
          const SizedBox(height: 4),
          Text(
            'Invest interest · ${proposal.status.label}',
            style: theme.textTheme.muted,
          ),
          if (onConfirm != null) ...[
            const SizedBox(height: 4),
            Text(
              'Tap Confirm below to apply this change.',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (proposal.add.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Add: ${proposal.add.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.remove.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remove: ${proposal.remove.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.setSymbols != null) ...[
            const SizedBox(height: 4),
            Text(
              'Set to: ${proposal.setSymbols!.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(proposal.rationale, style: theme.textTheme.small),
          ],
          if (proposal.applyError != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.applyError!,
              style: theme.textTheme.small.copyWith(
                color: BrandColors.lossOf(context),
              ),
            ),
          ],
          if (onConfirm != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            ProposalConfirmDismissActions(
              onConfirm: onConfirm,
              onDismiss: onDismiss,
              busy: busy,
            ),
          ],
        ],
      ),
    );
  }
}
