import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/formatting.dart';
import '../data/agents/agent_pnl_service.dart';

/// Compact profit / loss line for agent fill rollups (chat or Activity).
class AgentPnlStrip extends StatelessWidget {
  const AgentPnlStrip({
    super.key,
    required this.summary,
    this.leading,
    this.dense = false,
  });

  final AgentPnlSummary summary;
  final String? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasActivity) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    final prefix = leading?.trim();
    return Padding(
      padding: dense
          ? const EdgeInsets.symmetric(vertical: 2)
          : const EdgeInsets.only(bottom: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            [
              if (prefix != null && prefix.isNotEmpty) prefix,
              summary.symbol,
            ].join(' · '),
            style: theme.textTheme.small.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'profit ${formatMoney(summary.realizedProfit)}',
            style: theme.textTheme.small.copyWith(
              color: BrandColors.gainOf(context),
            ),
          ),
          Text(
            'loss ${formatMoney(summary.realizedLoss)}',
            style: theme.textTheme.small.copyWith(
              color: BrandColors.lossOf(context),
            ),
          ),
          if (summary.openBuyQty > 0)
            Text(
              'open ${summary.openBuyQty == summary.openBuyQty.roundToDouble() ? summary.openBuyQty.toInt() : summary.openBuyQty.toStringAsFixed(4)}',
              style: theme.textTheme.muted,
            ),
        ],
      ),
    );
  }
}
