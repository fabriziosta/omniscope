import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/settings/display_settings.dart';

/// Compact `title · meta` or comfortable title + muted subtitle for nav rows.
class DensityNavLeading extends StatelessWidget {
  const DensityNavLeading({
    super.key,
    required this.title,
    required this.meta,
    required this.density,
  });

  final String title;
  final String meta;
  final ListDensity density;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final compact = density == ListDensity.compact;

    if (compact) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title, style: theme.textTheme.large),
            TextSpan(
              text: '  ·  $meta',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.large),
        const SizedBox(height: 2),
        Text(meta, style: theme.textTheme.muted),
      ],
    );
  }
}
