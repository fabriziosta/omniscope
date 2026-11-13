import 'package:flutter/widgets.dart';

import '../data/settings/display_settings.dart';
import 'app_empty_view.dart';
import 'tappable_nav_row.dart';

/// Empty message or density-aware nav list for Markets / Crypto landings.
class GroupLandingBody extends StatelessWidget {
  const GroupLandingBody({
    super.key,
    required this.itemCount,
    required this.density,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  final int itemCount;
  final ListDensity density;
  final String emptyMessage;
  final Widget Function(BuildContext context, int index, bool compact)
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return AppEmptyView(emptyMessage);
    }

    final compact = density == ListDensity.compact;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: itemCount,
      separatorBuilder: (_, _) => SizedBox(height: compact ? 6 : 10),
      itemBuilder: (context, index) => itemBuilder(context, index, compact),
    );
  }
}

/// Convenience row wrapping [TappableNavRow] with density-aware leading.
class GroupLandingNavRow extends StatelessWidget {
  const GroupLandingNavRow({
    super.key,
    required this.onTap,
    required this.compact,
    required this.leading,
  });

  final VoidCallback onTap;
  final bool compact;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return TappableNavRow(
      onTap: onTap,
      compact: compact,
      leading: leading,
    );
  }
}
