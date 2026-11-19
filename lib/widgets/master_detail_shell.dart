import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/shell_navigation.dart';
import 'app_text.dart';
import 'app_tooltip.dart';
import 'in_tab_back.dart';

/// Master–detail layout for shell tabs (Markets, Portfolio, Activity, Agents,
/// Settings).
///
/// Content is always shown. Switching to this shell's bottom tab opens the
/// left nav automatically; the burger toggles it. System back closes the nav
/// when open.
///
/// - **Wide** (`>= [wideBreakpointDefault]`): animated side panel **pushes**
///   content (no scrim). Destination taps leave the nav open.
/// - **Narrow**: overlay drawer with dimmed barrier. Tap barrier or pick a
///   destination to close.
///
/// Only one content body should be mounted at a time — callers typically key
/// the content widget on [selected].
class MasterDetailShell<T> extends StatefulWidget {
  const MasterDetailShell({
    super.key,
    required this.selected,
    required this.sidebarBuilder,
    required this.contentBuilder,
    this.sidebarWidth = sidebarWidthDefault,
  });

  static const wideBreakpointDefault = 720.0;
  static const sidebarWidthDefault = 260.0;

  /// Current selection (always non-null when the shell is shown).
  final T selected;

  final Widget Function(
    BuildContext context,
    T highlighted, {
    required VoidCallback closeNav,
  }) sidebarBuilder;

  final Widget Function(
    BuildContext context,
    T item, {
    required VoidCallback onOpenMenu,
  }) contentBuilder;

  final double sidebarWidth;

  @override
  State<MasterDetailShell<T>> createState() => _MasterDetailShellState<T>();
}

class _MasterDetailShellState<T> extends State<MasterDetailShell<T>>
    with SingleTickerProviderStateMixin {
  static const _animDuration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _sizeFactor;
  bool _navOpen = false;

  ShellNavigationController? _shellNav;
  int? _myTabIndex;
  bool _wasActiveTab = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _animDuration);
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(curve);
    _sizeFactor = curve;
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _myTabIndex = ShellTabIndex.maybeOf(context);
    final shellNav = context.read<ShellNavigationController>();
    if (!identical(_shellNav, shellNav)) {
      _shellNav?.removeListener(_onShellNavChanged);
      _shellNav = shellNav;
      _shellNav!.addListener(_onShellNavChanged);
    }
    _syncNavForActiveTab();
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onShellNavChanged() => _syncNavForActiveTab();

  /// Open the drawer when this shell's bottom tab becomes the selected one
  /// (including the first time Markets is shown on launch).
  ///
  /// Skip auto-open when an Agents deep-link is pending so Investigate / Trade
  /// check land on the chat with the sidebar closed.
  void _syncNavForActiveTab() {
    final myTab = _myTabIndex;
    final shellNav = _shellNav;
    if (myTab == null || shellNav == null) return;

    final active = shellNav.tabIndex == myTab;
    if (active && !_wasActiveTab) {
      final skipOpen = myTab == ShellNavigationController.agentsTabIndex &&
          shellNav.pendingAgentChatOpen != null;
      if (!skipOpen) {
        // Defer so the first frame can mount content before the slide starts.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openNav();
        });
      }
    }
    _wasActiveTab = active;
  }

  void _openNav() {
    if (_navOpen) return;
    setState(() => _navOpen = true);
    _controller.forward();
  }

  void _closeNav() {
    if (!_navOpen) return;
    setState(() => _navOpen = false);
    _controller.reverse();
  }

  void _toggleNav() {
    if (_navOpen) {
      _closeNav();
    } else {
      _openNav();
    }
  }

  Widget _sidebarPanel({
    required BuildContext context,
    required double panelWidth,
    required VoidCallback closeNav,
    required bool elevate,
  }) {
    final theme = ShadTheme.of(context);
    return SizedBox(
      width: panelWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          border: Border(
            right: BorderSide(color: theme.colorScheme.border),
          ),
          boxShadow: elevate
              ? [
                  BoxShadow(
                    color: BrandColors.shadowOf(context),
                    blurRadius: 16,
                    offset: const Offset(4, 0),
                  ),
                ]
              : null,
        ),
        child: SafeArea(
          right: false,
          child: widget.sidebarBuilder(
            context,
            widget.selected,
            closeNav: closeNav,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return InTabBackEffect(
      onBack: _navOpen ? _closeNav : null,
      child: _MasterDetailNavScope(
        open: _navOpen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >=
                MasterDetailShell.wideBreakpointDefault;
            final panelWidth = widget.sidebarWidth.clamp(
              0.0,
              (constraints.maxWidth - 48).clamp(0.0, widget.sidebarWidth),
            );

            final content = widget.contentBuilder(
              context,
              widget.selected,
              onOpenMenu: _toggleNav,
            );

            if (wide) {
              // Push: animated width insets content; no scrim.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizeTransition(
                    sizeFactor: _sizeFactor,
                    axis: Axis.horizontal,
                    alignment: const Alignment(-1.0, -1.0),
                    child: _sidebarPanel(
                      context: context,
                      panelWidth: panelWidth,
                      closeNav: () {},
                      elevate: false,
                    ),
                  ),
                  Expanded(child: content),
                ],
              );
            }

            // Overlay: slide over full-bleed content with a dim barrier.
            return Stack(
              fit: StackFit.expand,
              children: [
                content,
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    if (_controller.isDismissed) {
                      return const SizedBox.shrink();
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        FadeTransition(
                          opacity: _fade,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeNav,
                            child: ColoredBox(
                              color: theme.colorScheme.foreground
                                  .withValues(alpha: 0.32),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SlideTransition(
                            position: _slide,
                            child: _sidebarPanel(
                              context: context,
                              panelWidth: panelWidth,
                              closeNav: _closeNav,
                              elevate: true,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Propagates nav open state so [MasterDetailMenuButton] can announce open/close.
class _MasterDetailNavScope extends InheritedWidget {
  const _MasterDetailNavScope({
    required this.open,
    required super.child,
  });

  final bool open;

  static bool isOpenOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_MasterDetailNavScope>()
            ?.open ??
        false;
  }

  @override
  bool updateShouldNotify(_MasterDetailNavScope oldWidget) =>
      open != oldWidget.open;
}

/// Standard padded sidebar list shared by master–detail shell tabs.
class MasterDetailNavList extends StatelessWidget {
  const MasterDetailNavList({
    super.key,
    required this.tiles,
    this.leading = const [],
    this.footer,
  });

  /// Optional widgets above the tiles (e.g. a soft CTA card).
  final List<Widget> leading;

  /// Destination rows — typically [MasterDetailNavTile]s.
  final List<Widget> tiles;

  /// Optional content pinned under the scrollable tiles (e.g. app version).
  final Widget? footer;

  static const tileGap = 4.0;
  static const listPadding = EdgeInsets.fromLTRB(10, 6, 10, 20);

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: footer == null
          ? listPadding
          : const EdgeInsets.fromLTRB(10, 6, 10, 6),
      children: [
        for (final child in leading) ...[
          child,
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: tileGap),
          tiles[i],
        ],
      ],
    );

    final footerWidget = footer;
    if (footerWidget == null) return list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          child: footerWidget,
        ),
      ],
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
    this.badge,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Optional muted line under [title] (e.g. symbol count).
  final String? meta;

  /// Optional chip after the title (e.g. Paper / Live).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    final tooltipMessage =
        meta == null || meta!.isEmpty ? title : '$title · $meta';

    return AppTooltip(
      message: tooltipMessage,
      wrapDetector: true,
      child: MouseRegion(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 24,
                        height: 24,
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
                          size: 13,
                          color: selected
                              ? theme.colorScheme.secondaryForeground
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: AppEllipsisText(
                                  title,
                                  maxLines: 2,
                                  style: theme.textTheme.p.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(width: 6),
                                badge!,
                              ],
                            ],
                          ),
                          if (meta != null) ...[
                            const SizedBox(height: 1),
                            AppEllipsisText(
                              meta!,
                              maxLines: 1,
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
                      size: 14,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content chrome: burger menu, title, subtitle, optional trailing, then body.
class MasterDetailContentPane extends StatelessWidget {
  const MasterDetailContentPane({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onOpenMenu,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onOpenMenu;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
          child: Row(
            children: [
              MasterDetailMenuButton(onPressed: onOpenMenu),
              const SizedBox(width: 4),
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
        Expanded(child: body),
      ],
    );
  }
}

/// Ghost burger control used by master–detail content chrome.
class MasterDetailMenuButton extends StatelessWidget {
  const MasterDetailMenuButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final open = _MasterDetailNavScope.isOpenOf(context);
    return Semantics(
      button: true,
      label: open ? 'Close menu' : 'Open menu',
      child: ShadButton.ghost(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: const Icon(LucideIcons.menu, size: 20),
      ),
    );
  }
}
