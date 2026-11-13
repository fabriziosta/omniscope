import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Size-aware master–detail layout for Settings, Markets, and Crypto.
///
/// Wide (≥ [wideBreakpoint]): persistent sidebar + content pane.
/// Narrow: nav list, then content with Back (in-tab; no route push).
///
/// Only one content body should be mounted at a time — callers typically key
/// the content widget on [selected] / [narrowSelected].
class MasterDetailShell<T> extends StatelessWidget {
  const MasterDetailShell({
    super.key,
    required this.selected,
    required this.narrowSelected,
    required this.onNarrowBack,
    required this.sidebarBuilder,
    required this.contentBuilder,
    this.wideBreakpoint = wideBreakpointDefault,
    this.sidebarWidth = sidebarWidthDefault,
  });

  static const wideBreakpointDefault = 720.0;
  static const sidebarWidthDefault = 260.0;

  /// Selection used in the wide layout (always non-null).
  final T selected;

  /// Narrow selection; `null` shows the sidebar list only.
  final T? narrowSelected;

  final VoidCallback onNarrowBack;

  /// [highlighted] is the current selection on wide, or `null` on the narrow
  /// list (no row selected until the user opens a pane).
  final Widget Function(
    BuildContext context,
    T? highlighted, {
    required bool wide,
  }) sidebarBuilder;

  final Widget Function(
    BuildContext context,
    T item, {
    required bool showBack,
    VoidCallback? onBack,
  }) contentBuilder;

  final double wideBreakpoint;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: sidebarWidth,
                child: sidebarBuilder(context, selected, wide: true),
              ),
              Container(
                width: 1,
                color: theme.colorScheme.border,
              ),
              Expanded(
                child: contentBuilder(
                  context,
                  selected,
                  showBack: false,
                  onBack: null,
                ),
              ),
            ],
          );
        }

        final narrowItem = narrowSelected;
        if (narrowItem == null) {
          return sidebarBuilder(context, null, wide: false);
        }

        return contentBuilder(
          context,
          narrowItem,
          showBack: true,
          onBack: onNarrowBack,
        );
      },
    );
  }
}

/// Settings-style sidebar row with optional leading icon and selected chrome.
class MasterDetailNavTile extends StatelessWidget {
  const MasterDetailNavTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.meta,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Optional muted line under [title] (e.g. symbol count).
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.border,
              ),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                                .withValues(alpha: 0.12)
                            : theme.colorScheme.secondary,
                        borderRadius: theme.radius,
                      ),
                      child: Icon(
                        icon,
                        size: 15,
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.large.copyWith(
                            color: foreground,
                          ),
                        ),
                        if (meta != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.small.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content chrome: optional Back, title, subtitle, optional trailing, then body.
class MasterDetailContentPane extends StatelessWidget {
  const MasterDetailContentPane({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    this.showBack = false,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.border),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(showBack ? 8 : 20, 8, 12, 12),
            child: Row(
              children: [
                if (showBack) ...[
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: onBack,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.h4),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.small.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}
