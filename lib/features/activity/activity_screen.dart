import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_pnl_service.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/market/market_data_client.dart';
import '../../data/notifications/app_notification.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../widgets/agent_pnl_strip.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import 'activity_operation_detail.dart';
import 'activity_operation_tile.dart';

/// Sidebar destinations for Activity. Only one body is mounted at a time.
enum ActivityNavSection {
  alerts,
  pending,
  history,
}

extension ActivityNavSectionX on ActivityNavSection {
  String get title => switch (this) {
        ActivityNavSection.alerts => 'Alerts',
        ActivityNavSection.pending => 'Pending',
        ActivityNavSection.history => 'History',
      };

  String get subtitle => switch (this) {
        ActivityNavSection.alerts =>
          'Scheduled runs, Autopilot stops, and setup reminders.',
        ActivityNavSection.pending =>
          'Open a chat to Confirm or Dismiss pending suggestions.',
        ActivityNavSection.history =>
          'Completed and non-actionable agent operations.',
      };

  IconData get icon => switch (this) {
        ActivityNavSection.alerts => LucideIcons.circleAlert,
        ActivityNavSection.pending => LucideIcons.circleDot,
        ActivityNavSection.history => LucideIcons.history,
      };
}

/// Shell tab: historical archive of agent discoveries and operations.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ShellNavigationController? _shellNav;
  ActivityNavSection? _section;
  String? _selectedProposalId;
  String? _filterPortfolioId;
  TradeProposalStatus? _filterStatus;

  _ActivityFilteredListsCache? _filteredListsCache;

  static const _statusFilters = <TradeProposalStatus?>[
    null,
    TradeProposalStatus.pending,
    TradeProposalStatus.executed,
    TradeProposalStatus.dismissed,
    TradeProposalStatus.failed,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shellNav = context.read<ShellNavigationController>();
    if (!identical(_shellNav, shellNav)) {
      _shellNav?.removeListener(_onShellNavChanged);
      _shellNav = shellNav;
      _shellNav!.addListener(_onShellNavChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeApplyActivityDeepLink();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() => _maybeApplyActivityDeepLink();

  void _maybeApplyActivityDeepLink() {
    if (!mounted) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.activityTabIndex) {
      return;
    }

    final openAlerts = shellNav.takePendingActivityOpenAlerts();
    if (openAlerts) {
      setState(() {
        _section = ActivityNavSection.alerts;
        _selectedProposalId = null;
      });
    }

    final proposalId = shellNav.takePendingActivityProposalId();
    if (proposalId == null || proposalId.isEmpty) return;

    final proposals = context.read<TradeProposalRepository>();
    final investInterest = context.read<InvestInterestProposalRepository>();
    final trade = proposals.byId(proposalId);
    final invest = investInterest.byId(proposalId);
    final section = _sectionForProposal(trade: trade, invest: invest);

    setState(() {
      _selectedProposalId = proposalId;
      if (section != null) _section = section;
    });
  }

  Future<void> _openAlert(AppNotification item) async {
    final repo = context.read<AppNotificationRepository>();
    final shellNav = context.read<ShellNavigationController>();
    if (!item.isSticky) {
      await repo.markRead(item.id);
    }
    if (!mounted) return;
    if (item.isSticky) {
      shellNav.goToSettings(sectionId: 'connections');
      return;
    }
    final chatId = _resolveAlertChatId(item);
    shellNav.goToAgentChat(
      chatId: chatId,
      roleId: item.roleId,
      symbol: item.symbol,
      notificationId: item.id,
    );
  }

  String? _resolveAlertChatId(AppNotification item) {
    final direct = item.chatId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final proposalId = item.proposalId?.trim();
    String? chatId;
    String? sourceMessageId;
    if (proposalId != null && proposalId.isNotEmpty) {
      final trade = context.read<TradeProposalRepository>().byId(proposalId);
      chatId = trade?.chatId;
      sourceMessageId = trade?.sourceMessageId;
      if (chatId == null || chatId.isEmpty) {
        final invest =
            context.read<InvestInterestProposalRepository>().byId(proposalId);
        chatId = invest?.chatId;
        sourceMessageId ??= invest?.sourceMessageId;
      }
    }

    final thread = context.read<AgentChatRepository>().findThread(
          chatId: chatId,
          sourceMessageId: sourceMessageId,
        );
    return thread?.chatId ?? chatId;
  }

  ActivityNavSection? _sectionForProposal({
    TradeProposal? trade,
    InvestInterestProposal? invest,
  }) {
    if (invest != null) {
      return invest.status == InvestInterestProposalStatus.pending
          ? ActivityNavSection.pending
          : ActivityNavSection.history;
    }
    if (trade != null) {
      final pendingActionable = trade.status == TradeProposalStatus.pending &&
          trade.side != TradeProposalSide.hold &&
          trade.quantity > 0;
      return pendingActionable
          ? ActivityNavSection.pending
          : ActivityNavSection.history;
    }
    return null;
  }

  TradeProposalActions _actions(BuildContext context) {
    return TradeProposalActions(
      appSettings: context.read<AgentAppSettings>(),
      proposals: context.read<TradeProposalRepository>(),
      activity: context.read<AgentActivityRepository>(),
      tradeExecutor: context.read<TradeExecutor>(),
      marketData: context.read<MarketDataClient>(),
      portfolio: context.read<PortfolioRepository>(),
      chats: context.read<AgentChatRepository>(),
      notifications: context.read<AppNotificationRepository>(),
    );
  }

  String _roleTitle(AgentsRepository agents, String roleId) {
    for (final r in agents.availableRoles) {
      if (r.id == roleId) return r.title;
    }
    return roleId;
  }

  String _portfolioLabel(TradeProposalActions actions, String exchangeId) {
    return actions.portfolioDisplayName(exchangeId);
  }

  String _statusFilterLabel(TradeProposalStatus? s) {
    if (s == null) return 'All status';
    return s.dashboardLabel;
  }

  void _openChat({
    required String roleId,
    String? chatId,
    String? sourceMessageId,
  }) {
    final chats = context.read<AgentChatRepository>();
    final existing = chats.findThread(
      chatId: chatId,
      sourceMessageId: sourceMessageId,
    );
    if (existing == null) {
      showAppToast(
        context,
        description: 'That chat no longer exists on this device.',
      );
      return;
    }
    context.read<ShellNavigationController>().goToAgentChat(
          chatId: existing.chatId,
          starterRoleId: roleId,
        );
  }

  /// Permanently removes a trade or Invest interest operation from Activity.
  Future<void> _deleteOperation(String proposalId) async {
    final trades = context.read<TradeProposalRepository>();
    final invest = context.read<InvestInterestProposalRepository>();
    final activity = context.read<AgentActivityRepository>();

    final removedTrade = await trades.delete(proposalId);
    final removedInvest =
        removedTrade ? false : await invest.delete(proposalId);
    if (!removedTrade && !removedInvest) return;

    await activity.deleteForProposal(proposalId);
    if (!mounted) return;
    if (_selectedProposalId == proposalId) {
      setState(() => _selectedProposalId = null);
    }
    showAppToast(context, description: 'Operation removed from Activity.');
  }

  /// Operation timeline only — exclude chat-message noise.
  List<AgentActivityEvent> _operationEvents(
    AgentActivityRepository activity,
    String proposalId,
  ) {
    return [
      for (final e in activity.forProposal(proposalId))
        if (e.kind != AgentActivityKind.messageSent) e,
    ];
  }

  bool _matchesFilters(TradeProposal p) {
    if (_filterPortfolioId != null && p.exchangeId != _filterPortfolioId) {
      return false;
    }
    if (_filterStatus != null && p.status != _filterStatus) return false;
    return true;
  }

  _ActivityFilteredLists _filteredListsFor({
    required TradeProposalRepository proposals,
    required InvestInterestProposalRepository investInterest,
  }) {
    final key = _ActivityFilteredListsCacheKey(
      tradeFingerprint: _tradeProposalFingerprint(proposals.proposals),
      investFingerprint:
          _investInterestProposalFingerprint(investInterest.proposals),
      filterPortfolioId: _filterPortfolioId,
      filterStatus: _filterStatus,
    );
    final cached = _filteredListsCache;
    if (cached != null && cached.key == key) return cached.lists;

    final pending = [
      for (final p in proposals.pendingActionable)
        if (_matchesFilters(p)) p,
    ];
    final pendingInvestInterest = [
      for (final p in investInterest.pendingActionable)
        if (_matchesInvestInterestFilters(p)) p,
    ];
    final history = [
      for (final p in proposals.proposals)
        if (p.status != TradeProposalStatus.pending && _matchesFilters(p)) p,
    ];
    final investInterestHistory = [
      for (final p in investInterest.proposals)
        if (p.status != InvestInterestProposalStatus.pending &&
            _matchesInvestInterestFilters(p))
          p,
    ];
  final pendingNonActionable = [
      for (final p in proposals.proposals)
        if (p.status == TradeProposalStatus.pending &&
            (p.side == TradeProposalSide.hold || p.quantity <= 0) &&
            _matchesFilters(p))
          p,
    ];
    final historyTrades = [...history, ...pendingNonActionable];

    final lists = _ActivityFilteredLists(
      pending: pending,
      pendingInvestInterest: pendingInvestInterest,
      historyTrades: historyTrades,
      investInterestHistory: investInterestHistory,
    );
    _filteredListsCache = _ActivityFilteredListsCache(key: key, lists: lists);
    return lists;
  }

  bool _matchesInvestInterestFilters(InvestInterestProposal p) {
    // Invest interest proposals are not portfolio-scoped.
    if (_filterPortfolioId != null) return false;
    if (_filterStatus != null) {
      final mapped = switch (p.status) {
        InvestInterestProposalStatus.pending => TradeProposalStatus.pending,
        InvestInterestProposalStatus.confirmed => TradeProposalStatus.executed,
        InvestInterestProposalStatus.dismissed => TradeProposalStatus.dismissed,
        InvestInterestProposalStatus.failed => TradeProposalStatus.failed,
      };
      if (mapped != _filterStatus) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final activity = context.watch<AgentActivityRepository>();
    final proposals = context.watch<TradeProposalRepository>();
    final investInterest =
        context.watch<InvestInterestProposalRepository>();
    final notifications = context.watch<AppNotificationRepository>();
    final agents = context.watch<AgentsRepository>();
    final actions = _actions(context);
    final splitWide = MediaQuery.sizeOf(context).width >= 560;

    final alerts = notifications.active;
    final alertsCount = alerts.length;
    final unreadAlerts = notifications.unreadCount;
    final canDismissAllAlerts = notifications.dismissibleActive.isNotEmpty;

    final filtered = _filteredListsFor(
      proposals: proposals,
      investInterest: investInterest,
    );
    final pending = filtered.pending;
    final pendingInvestInterest = filtered.pendingInvestInterest;
    final historyTrades = filtered.historyTrades;
    final investInterestHistory = filtered.investInterestHistory;

    final pendingCount = pending.length + pendingInvestInterest.length;
    final historyCount =
        historyTrades.length + investInterestHistory.length;
    final hasPending = pendingCount > 0;
    final section = _section ??
        (unreadAlerts > 0
            ? ActivityNavSection.alerts
            : hasPending
                ? ActivityNavSection.pending
                : ActivityNavSection.history);

    final selectedTrade = _selectedProposalId == null
        ? null
        : proposals.byId(_selectedProposalId!);
    final selectedInvestInterest = _selectedProposalId == null
        ? null
        : investInterest.byId(_selectedProposalId!);
    final hasSelection =
        selectedTrade != null || selectedInvestInterest != null;
    final showDetailOnly =
        section != ActivityNavSection.alerts && !splitWide && hasSelection;
    final hasAnyData = proposals.proposals.isNotEmpty ||
        investInterest.proposals.isNotEmpty;

    Widget detailForSelection({required bool withBack}) {
      if (selectedInvestInterest != null) {
        return InvestInterestDetail(
          proposal: selectedInvestInterest,
          events: _operationEvents(activity, selectedInvestInterest.id),
          roleTitle: _roleTitle(agents, selectedInvestInterest.roleId),
          onBack: withBack
              ? () => setState(() => _selectedProposalId = null)
              : null,
          onOpenChat: () => _openChat(
            roleId: selectedInvestInterest.roleId,
            chatId: selectedInvestInterest.chatId,
            sourceMessageId: selectedInvestInterest.sourceMessageId,
          ),
          onDelete: () => _deleteOperation(selectedInvestInterest.id),
        );
      }
      final selected = selectedTrade!;
      return ProposalDetail(
        proposal: selected,
        events: _operationEvents(activity, selected.id),
        roleTitle: _roleTitle(agents, selected.roleId),
        portfolioLabel: _portfolioLabel(actions, selected.exchangeId),
        onBack: withBack
            ? () => setState(() => _selectedProposalId = null)
            : null,
        onOpenChat: () => _openChat(
          roleId: selected.roleId,
          chatId: selected.chatId,
          sourceMessageId: selected.sourceMessageId,
        ),
        onDelete: () => _deleteOperation(selected.id),
      );
    }

    return MasterDetailShell<ActivityNavSection>(
      selected: section,
      sidebarBuilder: (context, highlighted, {required closeNav}) {
        final venues = actions.tradableVenues;
        final showProposalFilters = highlighted != ActivityNavSection.alerts;
        return MasterDetailNavList(
          tiles: [
            for (final dest in ActivityNavSection.values)
              MasterDetailNavTile(
                title: dest.title,
                icon: dest.icon,
                meta: switch (dest) {
                  ActivityNavSection.alerts => '$alertsCount',
                  ActivityNavSection.pending => '$pendingCount',
                  ActivityNavSection.history => '$historyCount',
                },
                selected: highlighted == dest,
                onTap: () {
                  setState(() {
                    _section = dest;
                    if (!splitWide || dest == ActivityNavSection.alerts) {
                      _selectedProposalId = null;
                    }
                  });
                  closeNav();
                },
              ),
            if (showProposalFilters) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Text(
                  'Status',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final s in _statusFilters)
                MasterDetailNavTile(
                  title: _statusFilterLabel(s),
                  selected: _filterStatus == s,
                  onTap: () => setState(() => _filterStatus = s),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Text(
                  'Portfolio',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MasterDetailNavTile(
                title: 'All portfolios',
                selected: _filterPortfolioId == null,
                onTap: () => setState(() => _filterPortfolioId = null),
              ),
              for (final v in venues)
                MasterDetailNavTile(
                  title: v.displayName,
                  selected: _filterPortfolioId == v.id,
                  onTap: () => setState(() => _filterPortfolioId = v.id),
                ),
            ],
          ],
        );
      },
      contentBuilder: (context, selectedSection, {required onOpenMenu}) {
        if (showDetailOnly) {
          return InTabBackEffect(
            onBack: () => setState(() => _selectedProposalId = null),
            child: detailForSelection(withBack: true),
          );
        }

        if (selectedSection == ActivityNavSection.alerts) {
          return MasterDetailContentPane(
            key: const ValueKey(ActivityNavSection.alerts),
            title: selectedSection.title,
            subtitle: selectedSection.subtitle,
            onOpenMenu: onOpenMenu,
            trailing: canDismissAllAlerts
                ? ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () async {
                      await notifications.dismissAll();
                    },
                    child: const Text('Dismiss all'),
                  )
                : null,
            body: _AlertsList(
              alerts: alerts,
              onOpen: _openAlert,
              onDismiss: (id) => notifications.dismiss(id),
            ),
          );
        }

        return MasterDetailContentPane(
          key: ValueKey(selectedSection),
          title: selectedSection.title,
          subtitle: selectedSection.subtitle,
          onOpenMenu: onOpenMenu,
          body: _buildSplitOrList(
            theme: theme,
            agents: agents,
            actions: actions,
            activity: activity,
            section: selectedSection,
            pending: pending,
            pendingInvestInterest: pendingInvestInterest,
            history: historyTrades,
            investInterestHistory: investInterestHistory,
            selectedId: _selectedProposalId,
            selectedTrade: selectedTrade,
            selectedInvestInterest: selectedInvestInterest,
            splitWide: splitWide,
            hasAnyData: hasAnyData,
          ),
        );
      },
    );
  }

  Widget _buildSplitOrList({
    required ShadThemeData theme,
    required AgentsRepository agents,
    required TradeProposalActions actions,
    required AgentActivityRepository activity,
    required ActivityNavSection section,
    required List<TradeProposal> pending,
    required List<InvestInterestProposal> pendingInvestInterest,
    required List<TradeProposal> history,
    required List<InvestInterestProposal> investInterestHistory,
    required String? selectedId,
    required TradeProposal? selectedTrade,
    required InvestInterestProposal? selectedInvestInterest,
    required bool splitWide,
    required bool hasAnyData,
  }) {
    final list = _ActivityList(
      section: section,
      pending: pending,
      pendingInvestInterest: pendingInvestInterest,
      history: history,
      investInterestHistory: investInterestHistory,
      selectedId: selectedId,
      hasAnyData: hasAnyData,
      onSelect: (id) => setState(() => _selectedProposalId = id),
      onDelete: _deleteOperation,
      roleTitle: (roleId) => _roleTitle(agents, roleId),
      portfolioLabel: (exchangeId) =>
          _portfolioLabel(actions, exchangeId),
    );

    if (!splitWide) return list;

    Widget detail;
    if (selectedInvestInterest != null) {
      detail = InvestInterestDetail(
        proposal: selectedInvestInterest,
        events: _operationEvents(activity, selectedInvestInterest.id),
        roleTitle: _roleTitle(agents, selectedInvestInterest.roleId),
        onOpenChat: () => _openChat(
          roleId: selectedInvestInterest.roleId,
          chatId: selectedInvestInterest.chatId,
          sourceMessageId: selectedInvestInterest.sourceMessageId,
        ),
        onDelete: () => _deleteOperation(selectedInvestInterest.id),
      );
    } else if (selectedTrade != null) {
      detail = ProposalDetail(
        proposal: selectedTrade,
        events: _operationEvents(activity, selectedTrade.id),
        roleTitle: _roleTitle(agents, selectedTrade.roleId),
        portfolioLabel: _portfolioLabel(actions, selectedTrade.exchangeId),
        onOpenChat: () => _openChat(
          roleId: selectedTrade.roleId,
          chatId: selectedTrade.chatId,
          sourceMessageId: selectedTrade.sourceMessageId,
        ),
        onDelete: () => _deleteOperation(selectedTrade.id),
      );
    } else {
      detail = Center(
        child: Text(
          'Select an operation for details.',
          style: theme.textTheme.muted,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: list),
        Container(width: 1, color: theme.colorScheme.border),
        Expanded(flex: 4, child: detail),
      ],
    );
  }
}

class _AlertsList extends StatelessWidget {
  const _AlertsList({
    required this.alerts,
    required this.onOpen,
    required this.onDismiss,
  });

  final List<AppNotification> alerts;
  final ValueChanged<AppNotification> onOpen;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    if (alerts.isEmpty) {
      return const AppEmptyView(
        'No alerts yet. Scheduled runs without a pending proposal, Autopilot '
        'halts, and setup reminders appear here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final item in alerts) ...[
          _AlertTile(
            item: item,
            onOpen: () => onOpen(item),
            onDismiss: item.isSticky ? null : () => onDismiss(item.id),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Open a chat to review a run. Setup reminders stay until you add '
          'an API key.',
          style: theme.textTheme.muted,
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.item,
    required this.onOpen,
    this.onDismiss,
  });

  final AppNotification item;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = _formatAlertClock(item.createdAt.toLocal());
    final sticky = item.isSticky;
    final unread = !item.read;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unread) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
                ] else
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.p.copyWith(
                          fontWeight:
                              unread ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(item.body, style: theme.textTheme.muted),
                      const SizedBox(height: 4),
                      Text(
                        sticky
                            ? item.kind.label
                            : '${item.kind.label} · $timeLabel',
                        style: theme.textTheme.muted.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                if (onDismiss != null) ...[
                  ShadButton.ghost(
                    height: 44,
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 4),
                ],
                ShadButton(
                  height: 44,
                  onPressed: onOpen,
                  child: Text(sticky ? 'Open Settings' : 'Open'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.section,
    required this.pending,
    required this.pendingInvestInterest,
    required this.history,
    required this.investInterestHistory,
    required this.selectedId,
    required this.hasAnyData,
    required this.onSelect,
    required this.onDelete,
    required this.roleTitle,
    required this.portfolioLabel,
  });

  final ActivityNavSection section;
  final List<TradeProposal> pending;
  final List<InvestInterestProposal> pendingInvestInterest;
  final List<TradeProposal> history;
  final List<InvestInterestProposal> investInterestHistory;
  final String? selectedId;
  final bool hasAnyData;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final String Function(String roleId) roleTitle;
  final String Function(String exchangeId) portfolioLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    if (!hasAnyData) {
      return const AppEmptyView(
        'No agent operations yet. Start a chat on Agents and Run a symbol — '
        'pending and completed operations appear here.',
      );
    }

    final showingPending = section == ActivityNavSection.pending;
    final itemsEmpty = showingPending
        ? pending.isEmpty && pendingInvestInterest.isEmpty
        : history.isEmpty && investInterestHistory.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (itemsEmpty)
          Text(
            showingPending
                ? 'Nothing waiting for confirmation.'
                : 'No past operations yet.',
            style: theme.textTheme.muted,
          )
        else if (showingPending) ...[
          for (final p in pendingInvestInterest) ...[
            InvestInterestTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
              onDelete: () => onDelete(p.id),
            ),
            const SizedBox(height: 8),
          ],
          for (final p in pending) ...[
            ProposalTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              portfolioLabel: portfolioLabel(p.exchangeId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
              onDelete: () => onDelete(p.id),
            ),
            const SizedBox(height: 8),
          ],
        ] else ...[
          ..._pnlRollup(context),
          for (final p in investInterestHistory) ...[
            InvestInterestTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
              onDelete: () => onDelete(p.id),
            ),
            const SizedBox(height: 8),
          ],
          for (final p in history) ...[
            ProposalTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              portfolioLabel: portfolioLabel(p.exchangeId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
              onDelete: () => onDelete(p.id),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  List<Widget> _pnlRollup(BuildContext context) {
    final theme = ShadTheme.of(context);
    final summaries = AgentPnlService.summariesByRoleSymbol(history);
    if (summaries.isEmpty) return const [];
    return [
      Text('P&L by specialty · symbol', style: theme.textTheme.small),
      const SizedBox(height: 6),
      for (final summary in summaries)
        AgentPnlStrip(
          summary: summary,
          leading: roleTitle(summary.roleId ?? ''),
          dense: true,
        ),
      const SizedBox(height: 12),
    ];
  }
}

String _formatAlertClock(DateTime local) {
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class _ActivityFilteredLists {
  const _ActivityFilteredLists({
    required this.pending,
    required this.pendingInvestInterest,
    required this.historyTrades,
    required this.investInterestHistory,
  });

  final List<TradeProposal> pending;
  final List<InvestInterestProposal> pendingInvestInterest;
  final List<TradeProposal> historyTrades;
  final List<InvestInterestProposal> investInterestHistory;
}

class _ActivityFilteredListsCacheKey {
  const _ActivityFilteredListsCacheKey({
    required this.tradeFingerprint,
    required this.investFingerprint,
    required this.filterPortfolioId,
    required this.filterStatus,
  });

  final String tradeFingerprint;
  final String investFingerprint;
  final String? filterPortfolioId;
  final TradeProposalStatus? filterStatus;

  @override
  bool operator ==(Object other) {
    return other is _ActivityFilteredListsCacheKey &&
        tradeFingerprint == other.tradeFingerprint &&
        investFingerprint == other.investFingerprint &&
        filterPortfolioId == other.filterPortfolioId &&
        filterStatus == other.filterStatus;
  }

  @override
  int get hashCode => Object.hash(
        tradeFingerprint,
        investFingerprint,
        filterPortfolioId,
        filterStatus,
      );
}

class _ActivityFilteredListsCache {
  const _ActivityFilteredListsCache({
    required this.key,
    required this.lists,
  });

  final _ActivityFilteredListsCacheKey key;
  final _ActivityFilteredLists lists;
}

String _tradeProposalFingerprint(List<TradeProposal> items) {
  final buf = StringBuffer('${items.length}');
  for (final p in items) {
    buf
      ..write('|')
      ..write(p.id)
      ..write(':')
      ..write(p.status.index)
      ..write(':')
      ..write(p.exchangeId)
      ..write(':')
      ..write(p.side.index)
      ..write(':')
      ..write(p.quantity);
  }
  return buf.toString();
}

String _investInterestProposalFingerprint(List<InvestInterestProposal> items) {
  final buf = StringBuffer('${items.length}');
  for (final p in items) {
    buf
      ..write('|')
      ..write(p.id)
      ..write(':')
      ..write(p.status.index);
  }
  return buf.toString();
}
