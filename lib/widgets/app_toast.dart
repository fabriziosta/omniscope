import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shows a short notification popup for a key user operation.
///
/// Prefer this over calling [ShadToaster] directly so copy, placement, and
/// duration stay consistent (mobile-first: top center, above the shell).
void showAppToast(
  BuildContext context, {
  String? title,
  required String description,
  bool destructive = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final toaster = ShadToaster.maybeOf(context);
  if (toaster == null) return;

  final toast = destructive
      ? ShadToast.destructive(
          title: title == null ? null : Text(title),
          description: Text(description),
          alignment: Alignment.topCenter,
          duration: duration,
        )
      : ShadToast(
          title: title == null ? null : Text(title),
          description: Text(description),
          alignment: Alignment.topCenter,
          duration: duration,
        );
  toaster.show(toast);
}
