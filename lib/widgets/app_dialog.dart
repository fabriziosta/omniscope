import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// App-standard modal: [showShadDialog] plus focus on the first text field.
///
/// Prefer this over calling [showShadDialog] directly. When the dialog has a
/// text input (rename, paste import, credentials, search, …), that field gets
/// keyboard focus after open — including when launched from a popover/menu.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool autofocusPrimaryInput = true,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  ShadDialogVariant variant = ShadDialogVariant.primary,
  bool opaque = false,
  Color barrierColor = const Color(0xcc000000),
  String barrierLabel = '',
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  return showShadDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    variant: variant,
    opaque: opaque,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    builder: (dialogContext) {
      final content = builder(dialogContext);
      if (!autofocusPrimaryInput) return content;
      return _AutofocusPrimaryTextField(child: content);
    },
  );
}

/// Requests focus on the first [EditableText] under [context] after layout.
///
/// Used by [showAppDialog]; safe no-op when the subtree has no text field.
class _AutofocusPrimaryTextField extends StatefulWidget {
  const _AutofocusPrimaryTextField({required this.child});

  final Widget child;

  @override
  State<_AutofocusPrimaryTextField> createState() =>
      _AutofocusPrimaryTextFieldState();
}

class _AutofocusPrimaryTextFieldState extends State<_AutofocusPrimaryTextField> {
  @override
  void initState() {
    super.initState();
    // First frame: dialog is in the tree. Second frame: popover/menu dismissal
    // has released focus so requestFocus sticks (Rename from ⋯ menu, etc.).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
    });
  }

  void _focus() {
    if (!mounted) return;
    final focusNode = findFirstEditableFocusNode(context);
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Finds the first [EditableText] focus node under [context], or null.
@visibleForTesting
FocusNode? findFirstEditableFocusNode(BuildContext context) {
  FocusNode? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    if (widget is EditableText) {
      found = widget.focusNode;
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return found;
}
