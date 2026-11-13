import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/quotes/quotes_list_controller.dart';
import 'app_progress.dart';

/// Footer control for paged quote lists (Markets / Crypto).
class QuotesLoadMoreBar extends StatelessWidget {
  const QuotesLoadMoreBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final controller = context.watch<QuotesListController>();
    if (!controller.hasMore && !controller.loadingMore) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Column(
        children: [
          Text(
            'Showing ${controller.quotes.length} of ${controller.totalSymbols}',
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 10),
          if (controller.loadingMore) const AppProgress(compact: true)
          else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: controller.loadMore,
              child: const Text('Load more'),
            ),
        ],
      ),
    );
  }
}
