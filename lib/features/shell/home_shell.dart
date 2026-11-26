import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/app_error_controller.dart';
import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/in_tab_back.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/settings/user_config_store.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../activity/activity_screen.dart';
import '../agents/agent_schedule_coordinator.dart';
import '../agents/agents_screen.dart';
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

  /// Order matches [ShellNavigationController] indices:
  /// Home · Markets · Agents · Activity · Settings.
  static const _pages = <Widget>[
    PortfolioScreen(),
    MarketsScreen(),
    AgentsScreen(),
    ActivityScreen(),
    SettingsScreen(),
  ];

  /// Side tabs only — Agents is the center FAB ([_AgentsNavFab]).
  static const _sideTabs = <(int, String, String, IconData)>[
    (
      ShellNavigationController.homeTabIndex,
      'Portfolio',
      AppCopy.tabTooltipPortfolio,
      LucideIcons.wallet,
    ),
    (
      ShellNavigationController.marketsTabIndex,
      'Markets',
      AppCopy.tabTooltipMarkets,
      LucideIcons.lineChart,
    ),
    (
      ShellNavigationController.activityTabIndex,
      'Activity',
      AppCopy.tabTooltipActivity,
      LucideIcons.activity,
    ),
    (
      ShellNavigationController.settingsTabIndex,
      'Settings',
      AppCopy.tabTooltipSettings,
      LucideIcons.settings,
    ),
  ];

  static const _agentsFabSize = 56.0;
  static const _agentsFabProtrusion = 20.0;
  static const _agentsFabSlotWidth = 72.0;

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
        unawaited(context.read<UserConfigStore>().flushPersist());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<AppErrorController>().bindTabNavigators(_tabNavigatorKeys);
    context.read<ShellNavigationController>().bindTabNavigators(
          _tabNavigatorKeys,
        );
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
    final index = context.select<ShellNavigationController, int>(
      (nav) => nav.tabIndex,
    );

    return InTabBackScope(
      registry: _inTabBack,
      child: PopScope(
        // Always intercept: navigator → in-tab master–detail → exit.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = context.read<ShellNavigationController>();
          final tab = nav.tabIndex;
          if (_activeTabCanPop(tab)) {
            _tabNavigatorKeys[tab].currentState?.maybePop();
            return;
          }
          if (_inTabBack.handle(tab)) return;
          SystemNavigator.pop();
        },
        child: ColoredBox(
          color: theme.colorScheme.background,
          child: SafeArea(
            child: Column(
              children: [
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
                // Center Agents FAB protrudes above the bar into content.
                Padding(
                  padding: const EdgeInsets.only(top: _agentsFabProtrusion),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.background,
                          border: Border(
                            top: BorderSide(color: theme.colorScheme.border),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                        child: Row(
                          children: [
                            for (var i = 0; i < _sideTabs.length; i++) ...[
                              if (i == 2)
                                const SizedBox(width: _agentsFabSlotWidth)
                              else if (i > 0)
                                const SizedBox(width: 4),
                              Expanded(
                                child: _sideTabs[i].$1 ==
                                        ShellNavigationController
                                            .activityTabIndex
                                    ? _ActivityNavTab(
                                        label: _sideTabs[i].$2,
                                        tooltip: _sideTabs[i].$3,
                                        icon: _sideTabs[i].$4,
                                        selected: index == _sideTabs[i].$1,
                                        onPressed: () =>
                                            _onTabPressed(_sideTabs[i].$1),
                                      )
                                    : _NavTab(
                                        label: _sideTabs[i].$2,
                                        tooltip: _sideTabs[i].$3,
                                        icon: _sideTabs[i].$4,
                                        selected: index == _sideTabs[i].$1,
                                        onPressed: () =>
                                            _onTabPressed(_sideTabs[i].$1),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        top: -_agentsFabProtrusion,
                        child: _AgentsNavFabWithBadge(
                          size: _agentsFabSize,
                          selected: index ==
                              ShellNavigationController.agentsTabIndex,
                          onPressed: () => _onTabPressed(
                            ShellNavigationController.agentsTabIndex,
                          ),
                        ),
                      ),
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

/// Activity tab — unread alert badge only (narrow provider watch).
class _ActivityNavTab extends StatelessWidget {
  const _ActivityNavTab({
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
    final badgeCount = context.select<AppNotificationRepository, int>(
      (r) => r.unreadCount,
    );
    return _NavTab(
      label: label,
      tooltip: tooltip,
      icon: icon,
      selected: selected,
      badgeCount: badgeCount,
      onPressed: onPressed,
    );
  }
}

class _AgentsNavFabWithBadge extends StatelessWidget {
  const _AgentsNavFabWithBadge({
    required this.size,
    required this.selected,
    required this.onPressed,
  });

  final double size;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tradePending = context.select<TradeProposalRepository, int>(
      (r) => r.pendingActionableCount,
    );
    final investPending = context.select<InvestInterestProposalRepository, int>(
      (r) => r.pendingActionableCount,
    );
    return _AgentsNavFab(
      size: size,
      selected: selected,
      badgeCount: tradePending + investPending,
      onPressed: onPressed,
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
    this.badgeCount = 0,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final int badgeCount;

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
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(icon, size: 18, color: foreground),
                            if (badgeCount > 0)
                              Positioned(
                                top: -6,
                                right: -10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      badgeCount > 99 ? '99+' : '$badgeCount',
                                      style: theme.textTheme.small.copyWith(
                                        color: theme
                                            .colorScheme.primaryForeground,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

/// Center Agents CTA — primary circle that protrudes above the bottom bar.
class _AgentsNavFab extends StatelessWidget {
  const _AgentsNavFab({
    required this.size,
    required this.selected,
    required this.badgeCount,
    required this.onPressed,
  });

  final double size;
  final bool selected;
  final int badgeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    return AppTooltip(
      message: AppCopy.tabTooltipAgents,
      wrapDetector: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: size + 16,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                    border: Border.all(
                      color: selected
                          ? scheme.secondary
                          : scheme.background,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BrandColors.shadowOf(context),
                        blurRadius: selected ? 14 : 10,
                        spreadRadius: selected ? 1 : 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Icon(
                      LucideIcons.messagesSquare,
                      size: 26,
                      color: scheme.primaryForeground,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: scheme.background,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: theme.textTheme.small.copyWith(
                            color: scheme.secondaryForeground,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
