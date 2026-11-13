import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/app_error_controller.dart';
import 'app_fatal_error_screen.dart';

/// Replaces the navigator subtree with [AppFatalErrorScreen] when fatal.
///
/// Wire into [ShadApp.builder] so uncaught async failures cover the whole app
/// (including any pushed routes) without dumping exception text.
class AppErrorGate extends StatelessWidget {
  const AppErrorGate({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final errors = context.watch<AppErrorController>();
    if (errors.isActive) {
      return AppFatalErrorScreen(onGoHome: errors.goHome);
    }
    return child ?? const SizedBox.shrink();
  }
}
