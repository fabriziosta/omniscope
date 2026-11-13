import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Hover / long-press tooltip with matching [Semantics] label.
///
/// Set [wrapDetector] when [child] is not already a [ShadButton] (or other
/// shadcn hover target) so desktop hover can activate the tooltip.
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.wrapDetector = false,
  });

  final String message;
  final Widget child;

  /// When true, wraps [child] in [ShadGestureDetector] for hover hit-testing.
  final bool wrapDetector;

  @override
  Widget build(BuildContext context) {
    final target = wrapDetector ? ShadGestureDetector(child: child) : child;
    return Semantics(
      label: message,
      child: ShadTooltip(
        builder: (_) => Text(message),
        child: target,
      ),
    );
  }
}
