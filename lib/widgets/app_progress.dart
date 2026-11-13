import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Short indeterminate bar.
///
/// [ShadProgress] always expands to the full width of its parent and paints a
/// 16px track, so a host card, list, or header turns into one thick stripe.
/// This keeps a thin pill that stays a fraction of that host.
class AppProgress extends StatelessWidget {
  const AppProgress({super.key, this.compact = false});

  /// Header, chat, and footer slots. Section and page loaders use the default.
  final bool compact;

  static const _trackHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_trackHeight);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: _widthFor(constraints.maxWidth),
          child: ShadProgress(
            minHeight: _trackHeight,
            borderRadius: radius,
            innerBorderRadius: radius,
            semanticsLabel: 'Loading',
          ),
        );
      },
    );
  }

  double _widthFor(double maxWidth) {
    if (compact) return 56;
    if (!maxWidth.isFinite || maxWidth <= 0) return 140;
    return (maxWidth * 0.36).clamp(96.0, 160.0);
  }
}
