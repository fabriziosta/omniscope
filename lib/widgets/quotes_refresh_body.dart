import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/quotes/quotes_list_controller.dart';

/// Pull-to-refresh shell for quote list bodies (Markets / Crypto).
class QuotesRefreshBody extends StatelessWidget {
  const QuotesRefreshBody({
    super.key,
    required this.child,
    this.onRefresh,
  });

  final Widget child;

  /// Defaults to [QuotesListController.refresh] when omitted.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return RefreshIndicator(
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.background,
      onRefresh: onRefresh ??
          () => context.read<QuotesListController>().refresh(),
      child: child,
    );
  }
}
