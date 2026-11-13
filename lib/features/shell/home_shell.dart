import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/app_error_controller.dart';
import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../widgets/app_placeholder_icon.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/notification_inbox.dart';
import '../agents/agent_schedule_coordinator.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _inTabBack = InTabBackRegistry();

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

  static const _tabs = <(int, String, String, IconData)>[
    (0, 'Markets', AppCopy.tabTooltipMarkets, LucideIcons.lineChart),
    (1, 'Crypto', AppCopy.tabTooltipCrypto, LucideIcons.coins),
    (2, 'Portfolio', AppCopy.tabTooltipPortfolio, LucideIcons.wallet),
    (3, 'Agents', AppCopy.tabTooltipAgents, LucideIcons.bot),
    (4, 'Settings', AppCopy.tabTooltipSettings, LucideIcons.settings),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentScheduleCoordinator>().resume();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final schedule = context.read<AgentScheduleCoordinator>();
    switch (state) {
      case AppLifecycleState.resumed:
        schedule.resume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        schedule.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<AppErrorController>().bindTabNavigators(_tabNavigatorKeys);
  }

  void _onTabStackChanged() {
    if (mounted) setState(() {});
  }

  void _onTabPressed(int tabIndex) {
    final shellNav = context.read<ShellNavigationController>();
    if (shellNav.tabIndex == tabIndex) {
      _tabNavigatorKeys[tabIndex]
          .currentState
          ?.popUntil((route) => route.isFirst);
      return;
    }
    shellNav.selectTab(tabIndex);
  }

  bool _activeTabCanPop(int index) {
    final nav = _tabNavigatorKeys[index].currentState;
    return nav != null && nav.canPop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final index = context.watch<ShellNavigationController>().tabIndex;
    final wide = MediaQuery.sizeOf(context).width >=
        MasterDetailShell.wideBreakpointDefault;

    return InTabBackScope(
      registry: _inTabBack,
      child: PopScope(
        // Always intercept: navigator → in-tab master–detail → exit.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_activeTabCanPop(index)) {
            _tabNavigatorKeys[index].currentState?.maybePop();
            return;
          }
          if (_inTabBack.handle(index)) return;
          SystemNavigator.pop();
        },
        child: ColoredBox(
          color: theme.colorScheme.background,
          child: SafeArea(
            child: Column(
              children: [
                // Always show shell chrome so the notification bell is reachable
                // on phones; brand wordmark stays wide-only.
                _ShellHeader(showBrand: wide),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        _TabNavigator(
                          tabIndex: i,
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
                            tooltip: entry.$3,
                            icon: entry.$4,
                            selected: index == entry.$1,
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
      ),
    );
  }
}

/// Nested navigator so detail routes do not cover the shell bottom nav.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.tabIndex,
    required this.navigatorKey,
    required this.observer,
    required this.root,
  });

  final int tabIndex;
  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return ShellTabIndex(
      index: tabIndex,
      child: Navigator(
        key: navigatorKey,
        observers: [observer],
        onGenerateRoute: (settings) {
          return FadePageRoute<void>(
            settings: settings,
            builder: (_) => root,
          );
        },
      ),
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

/// Slim shell chrome — brand (wide) + always-visible notification bell.
class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.showBrand});

  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            if (showBrand) ...[
              const AppPlaceholderIcon(size: 24),
              const SizedBox(width: 10),
              Text('Omniscope', style: theme.textTheme.large),
            ] else ...[
              const AppPlaceholderIcon(size: 22),
            ],
            const Spacer(),
            const NotificationBellButton(),
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
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
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
    return AppTooltip(
      message: tooltip,
      wrapDetector: true,
      child: MouseRegion(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
                          style:
                              theme.textTheme.small.copyWith(color: foreground),
                        ),
                      ],
                    ),
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
