import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared separator / chevron / padding for feature accordion items.
class ThemedAccordionItem<T> extends StatelessWidget {
  const ThemedAccordionItem({
    super.key,
    required this.value,
    required this.title,
    required this.child,
  });

  final T value;
  final Widget title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadAccordionItem<T>(
      value: value,
      separator: Container(
        height: 1,
        color: theme.colorScheme.border,
      ),
      underlineTitleOnHover: false,
      padding: const EdgeInsets.symmetric(vertical: 12),
      icon: Icon(
        LucideIcons.chevronDown,
        size: 16,
        color: theme.colorScheme.mutedForeground,
      ),
      title: title,
      child: child,
    );
  }
}
