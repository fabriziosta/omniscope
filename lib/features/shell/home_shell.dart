import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../widgets/symbol_search.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../activity/activity_screen.dart';
import '../agents/agent_schedule_coordinator.dart';
import '../agents/agents_screen.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../landing/landing_screen.dart';
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
    PortfolioScreen(),
    ActivityScreen(),
    AgentsScreen(),
    SettingsScreen(),
  ];

  static const _tabs = <(int, String, String, IconData)>[
    (0, 'Markets', AppCopy.tabTooltipMarkets, LucideIcons.lineChart),
    (1, 'Portfolio', AppCopy.tabTooltipPortfolio, LucideIcons.wallet),
    (2, 'Activity', AppCopy.tabTooltipActivity, LucideIcons.activity),
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
    if (!shellNav.showLanding && shellNav.tabIndex == tabIndex) {
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

  void _openSymbolFromSearch(String symbol, int tabIndex) {
    final shellNav = context.read<ShellNavigationController>();
    if (shellNav.showLanding) {
      shellNav.selectTab(ShellNavigationController.marketsTabIndex);
      tabIndex = ShellNavigationController.marketsTabIndex;
    }
    // Nested navigator may not be mounted until after the tab switch rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _tabNavigatorKeys[tabIndex].currentState;
      if (nav == null) return;
      nav.push<void>(
        FadePageRoute<void>(
          builder: (_) => AssetDetailScreen(symbol: symbol),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final shellNav = context.watch<ShellNavigationController>();
    final index = shellNav.tabIndex;
    final showLanding = shellNav.showLanding;
    final pendingCount =
        context.watch<TradeProposalRepository>().pendingActionableCount +
            context
                .watch<InvestInterestProposalRepository>()
                .pendingActionableCount;
    final wide = MediaQuery.sizeOf(context).width >=
        MasterDetailShell.wideBreakpointDefault;

    return InTabBackScope(
      registry: _inTabBack,
      child: PopScope(
        // Always intercept: landing → navigator → in-tab master–detail → exit.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = context.read<ShellNavigationController>();
          if (nav.showLanding) {
            if (nav.hasEnteredTab) {
              nav.dismissLanding();
              return;
            }
            SystemNavigator.pop();
            return;
          }
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
                // Always show shell chrome so search + notification bell are
                // reachable on phones; brand wordmark stays wide-only.
                _ShellHeader(
                  showBrand: wide,
                  onBrandTap: () =>
                      context.read<ShellNavigationController>().goToLanding(),
                  onSymbolSelected: (symbol) =>
                      _openSymbolFromSearch(symbol, index),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Keep tab navigators mounted so brand → landing → back
                      // does not reset Markets / Agents state. Skip building
                      // them on the initial cold-start landing so quote-fetch
                      // timers are not started until the user opens a tab.
                      if (!showLanding || shellNav.hasEnteredTab)
                        Offstage(
                          offstage: showLanding,
                          child: TickerMode(
                            enabled: !showLanding,
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
                        ),
                      if (showLanding) const LandingScreen(),
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
                            selected:
                                !showLanding && index == entry.$1,
                            badgeCount: entry.$1 ==
                                    ShellNavigationController.agentsTabIndex
                                ? pendingCount
                                : 0,
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

/// Slim shell chrome — brand (wide) + symbol search + notification bell.
class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.showBrand,
    required this.onBrandTap,
    required this.onSymbolSelected,
  });

  final bool showBrand;
  final VoidCallback onBrandTap;
  final ValueChanged<String> onSymbolSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBrandTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppPlaceholderIcon(size: showBrand ? 24 : 22),
                    if (showBrand) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Omniscope',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: theme.textTheme.large.fontSize ?? 18,
                          fontWeight: FontWeight.w600,
                          height: theme.textTheme.large.height,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            SymbolSearchButton(onSymbolSelected: onSymbolSelected),
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
