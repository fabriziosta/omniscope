import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Title + muted subtitle used at the top of shell tab roots.
class TabPageHeader extends StatelessWidget {
  const TabPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleSpacing = 4,
  });

  final String title;
  final String subtitle;
  final double subtitleSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.h3),
          SizedBox(height: subtitleSpacing),
          Text(subtitle, style: theme.textTheme.muted),
        ],
      ),
    );
  }
}
