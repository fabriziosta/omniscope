import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'metric_stat.dart';

/// Visual tone for portfolio summary cards.
enum SummaryWellTone { paper, live }

/// Eyebrow / blurb / big total / optional 3-stat row for Portfolio wells.
class SummaryWell extends StatelessWidget {
  const SummaryWell({
    super.key,
    required this.tone,
    required this.eyebrow,
    required this.blurb,
    required this.totalLabel,
    required this.totalValue,
    this.trailing,
    this.stats = const [],
    this.footer,
  });

  final SummaryWellTone tone;
  final String eyebrow;
  final String blurb;
  final String totalLabel;
  final String totalValue;
  final Widget? trailing;
  final List<MetricStat> stats;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isPaper = tone == SummaryWellTone.paper;
    final fill = isPaper
        ? theme.colorScheme.secondary.withValues(alpha: 0.45)
        : theme.colorScheme.primary.withValues(alpha: 0.08);
    final border = isPaper ? theme.colorScheme.border : theme.colorScheme.primary;
    final eyebrowColor = isPaper
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    eyebrow,
                    style: theme.textTheme.small.copyWith(
                      color: eyebrowColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            Text(blurb, style: theme.textTheme.muted),
            const SizedBox(height: 12),
            Text(totalLabel, style: theme.textTheme.muted),
            const SizedBox(height: 4),
            Text(totalValue, style: theme.textTheme.h3),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final stat in stats) Expanded(child: stat),
                ],
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
