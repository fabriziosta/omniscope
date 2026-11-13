import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_error_view.dart';

/// Full-screen recovery page after an uncaught async failure.
class AppFatalErrorScreen extends StatelessWidget {
  const AppFatalErrorScreen({super.key, required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.maybeOf(context);
    final body = AppErrorView(
      title: 'Something went wrong',
      message:
          'An unexpected problem stopped this screen. '
          'You can go home and keep exploring.',
      onRetry: onGoHome,
      retryLabel: 'Go home',
    );

    if (theme == null) return body;

    return ColoredBox(
      color: theme.colorScheme.background,
      child: body,
    );
  }
}
