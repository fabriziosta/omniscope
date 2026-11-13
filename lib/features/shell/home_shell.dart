import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_error_controller.dart';
import '../../core/fade_page_route.dart';
import '../../widgets/app_placeholder_icon.dart';
import '../../widgets/master_detail_shell.dart';
import '../agents/agents_screen.dart';
import '../crypto/crypto_group_screen.dart';
import '../markets/markets_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  /// One stack per tab so pushes stay above the bottom nav.
  late final List<GlobalKey<NavigatorState>> _tabNavigatorKeys = List.generate(
    _pages.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// Rebuild when a tab stack changes so [PopScope.canPop] stays accurate.
  late final List<_TabRouteObserver> _tabObservers = List.generate(
    _pages.length,
    (_) => _TabRouteObserver(_onTabStackChanged),
  );

  static const _pages = <Widget>[
    MarketsScreen(),
    CryptoGroupScreen(),
    PortfolioScreen(),
    AgentsScreen(),
    SettingsScreen(),
  ];

  static const _tabs = <(int, String, IconData)>[
    (0, 'Markets', LucideIcons.lineChart),
    (1, 'Crypto', LucideIcons.coins),
    (2, 'Portfolio', LucideIcons.wallet),
    (3, 'Agents', LucideIcons.bot),
    (4, 'Settings', LucideIcons.settings),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<AppErrorController>().bindTabNavigators(_tabNavigatorKeys);
  }

  void _onTabStackChanged() {
    if (mounted) setState(() {});
  }

  void _onTabPressed(int tabIndex) {
    if (_index == tabIndex) {
      _tabNavigatorKeys[tabIndex]
          .currentState
          ?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = tabIndex);
  }

  bool get _activeTabCanPop {
    final nav = _tabNavigatorKeys[_index].currentState;
    return nav != null && nav.canPop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final showBrandHeader =
        MediaQuery.sizeOf(context).width >=
        MasterDetailShell.wideBreakpointDefault;

    return PopScope(
      // Keep the shell mounted; pop the active tab stack first.
      canPop: !_activeTabCanPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _tabNavigatorKeys[_index].currentState?.maybePop();
      },
      child: ColoredBox(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Column(
            children: [
              // Wide only — reclaim ~52px on phones; tab titles stay.
              if (showBrandHeader) const _ShellHeader(),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      _TabNavigator(
                        navigatorKey: _tabNavigatorKeys[i],
                        observer: _tabObservers[i],
                        root: _pages[i],
                      ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.border),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Row(
                  children: [
                    for (final entry in _tabs) ...[
                      if (entry.$1 > 0) const SizedBox(width: 4),
                      Expanded(
                        child: _NavTab(
                          label: entry.$2,
                          icon: entry.$3,
                          selected: _index == entry.$1,
                          onPressed: () => _onTabPressed(entry.$1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nested navigator so detail routes do not cover the shell bottom nav.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.observer,
    required this.root,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [observer],
      onGenerateRoute: (settings) {
        return FadePageRoute<void>(
          settings: settings,
          builder: (_) => root,
        );
      },
    );
  }
}

class _TabRouteObserver extends NavigatorObserver {
  _TabRouteObserver(this.onChanged);

  final VoidCallback onChanged;

  void _notify() {
    // Initial route install runs during build; defer so the shell can rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Skip the tab's first route — only detail pushes matter for PopScope.
    if (previousRoute != null) _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

/// Slim brand bar for wide layouts — compact glyph + wordmark.
class _ShellHeader extends StatelessWidget {
  const _ShellHeader();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const AppPlaceholderIcon(size: 24),
            const SizedBox(width: 10),
            Text('Omniscope', style: theme.textTheme.large),
          ],
        ),
      ),
    );
  }
}

/// Compact bottom-nav control that scales labels on narrow phones.
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;

    // Avoid ShadButton's intrinsic Row here: labels do not fit phone
    // width with default button padding, and the inner Row will overflow.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        style: theme.textTheme.small.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
