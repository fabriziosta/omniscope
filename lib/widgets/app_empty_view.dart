import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Centered muted empty state for lists and group landings.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView(
    this.message, {
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          style: theme.textTheme.muted,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
