import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/app_copy.dart';

/// Symbol filter for Markets / Crypto quote lists.
///
/// Sits as a sticky chrome strip under the pane title (not floating inside the
/// scroll list), with search icon + optional clear.
class QuotesFilterField extends StatefulWidget {
  const QuotesFilterField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hint = AppCopy.filterQuotesHint,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  @override
  State<QuotesFilterField> createState() => _QuotesFilterFieldState();
}

class _QuotesFilterFieldState extends State<QuotesFilterField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(QuotesFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasQuery = widget.controller.text.trim().isNotEmpty;

    // Border only — no drop shadow (shadow paints over the list without
    // reserving layout space and hides the first rows).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: ShadInput(
            controller: widget.controller,
            placeholder: Text(widget.hint),
            onChanged: widget.onChanged,
            leading: Icon(
              LucideIcons.search,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
            trailing: hasQuery
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clear,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Icon(
                          LucideIcons.x,
                          size: 16,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Case-insensitive symbol / name filter for quote lists.
List<T> filterBySymbolQuery<T>({
  required List<T> items,
  required String query,
  required String Function(T item) symbolOf,
  String? Function(T item)? nameOf,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return [
    for (final item in items)
      if (symbolOf(item).toLowerCase().contains(q) ||
          (nameOf?.call(item)?.toLowerCase().contains(q) ?? false))
        item,
  ];
}
