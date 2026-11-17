import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_text.dart';

/// Compact label + value column used in summary wells and asset meta rows.
class MetricStat extends StatelessWidget {
  const MetricStat({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppEllipsisText(
          label,
          maxLines: 2,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 2),
        AppMoneyText(
          value,
          textAlign: TextAlign.start,
          style: theme.textTheme.small.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
