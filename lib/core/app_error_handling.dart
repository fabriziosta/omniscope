import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../widgets/app_error_view.dart';
import 'app_error_controller.dart';

/// Installs friendly global error UI. Call once from [main] before [runApp].
///
/// - Build failures render [AppErrorView.crash] instead of the exception dump.
/// - Uncaught async errors log and redirect via [AppErrorController].
/// Real exception details stay in the debug console / logs only.
void installAppErrorHandling(AppErrorController errors) {
  ErrorWidget.builder = (details) {
    if (kDebugMode) {
      // Keep the real failure visible to developers in the console.
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    }
    return const AppErrorView.crash();
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    errors.reportUnhandled(error, stack);
    return true;
  };
}
