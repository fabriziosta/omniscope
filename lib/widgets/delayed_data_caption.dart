import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/app_copy.dart';

/// Muted delayed-data / as-of line used under Markets, Favorites, Crypto, etc.
///
/// Default padding keeps the caption clear of the pane header / filter border
/// above and gives a little air before the quote list.
class DelayedDataCaption extends StatelessWidget {
  const DelayedDataCaption({
    super.key,
    this.fetchedAt,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  /// When null, only [AppCopy.delayedDataCaption] is shown.
  final DateTime? fetchedAt;

  /// Outer inset. Defaults clear the pane header / filter border above; lists
  /// keep their own top padding for space below. Use a custom inset when
  /// embedding inline (e.g. asset detail).
  final EdgeInsetsGeometry padding;

  static String formatAsOf(DateTime time) {
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String labelFor(DateTime? fetchedAt) {
    if (fetchedAt == null) return AppCopy.delayedDataCaption;
    return '${AppCopy.delayedDataCaption} As of ${formatAsOf(fetchedAt)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        labelFor(fetchedAt),
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.mutedForeground,
          height: 1.35,
        ),
      ),
    );
  }
}
