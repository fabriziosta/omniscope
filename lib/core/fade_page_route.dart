import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';

/// Fade transition used for tab roots and detail pushes.
///
/// Each page is wrapped in [SelectionArea] so static [Text] is selectable.
class FadePageRoute<T> extends PageRouteBuilder<T> {
  FadePageRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              SelectionArea(child: builder(context)),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
}

/// Pushes [page] with a fade transition.
Future<T?> pushFadePage<T extends Object?>(
  BuildContext context,
  Widget page,
) {
  return Navigator.of(context).push<T>(
    FadePageRoute<T>(builder: (_) => page),
  );
}
