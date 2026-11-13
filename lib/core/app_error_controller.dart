import 'package:flutter/widgets.dart';

/// Holds uncaught-async fatal state for a full-screen recovery overlay.
///
/// Build failures still use [ErrorWidget.builder] / [AppErrorView.crash] in place.
/// This controller is for zone / platform async errors that would otherwise
/// leave the user on a broken screen with no recovery path.
class AppErrorController extends ChangeNotifier {
  AppErrorController({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  /// Nested tab stacks from [HomeShell]; cleared on [goHome].
  List<GlobalKey<NavigatorState>> _tabNavigatorKeys = const [];

  var _active = false;

  /// True while the fatal error overlay should be shown.
  bool get isActive => _active;

  /// Wire shell tab navigators so recovery can clear nested routes.
  void bindTabNavigators(List<GlobalKey<NavigatorState>> keys) {
    _tabNavigatorKeys = keys;
  }

  /// Log and show the fatal error overlay. Idempotent while active.
  void reportUnhandled(Object error, StackTrace stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Dismiss the overlay and pop root + tab stacks back to the shell.
  void goHome() {
    if (!_active) return;
    _active = false;
    notifyListeners();
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    for (final key in _tabNavigatorKeys) {
      key.currentState?.popUntil((route) => route.isFirst);
    }
  }
}
