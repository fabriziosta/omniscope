import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/formatting.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/agent_pnl_service.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/market/market_data_client.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/mandate_settings.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/agent_pnl_strip.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';

/// Sidebar destinations for Activity. Only one body is mounted at a time.
enum ActivityNavSection {
  pending,
  history,
}

extension ActivityNavSectionX on ActivityNavSection {
  String get title => switch (this) {
        ActivityNavSection.pending => 'Pending',
        ActivityNavSection.history => 'History',
      };

  String get subtitle => switch (this) {
        ActivityNavSection.pending =>
          'Open a chat to Confirm or Dismiss pending suggestions.',
        ActivityNavSection.history =>
          'Completed and non-actionable agent operations.',
      };

  IconData get icon => switch (this) {
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
      _maybeOpenPendingProposal();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() => _maybeOpenPendingProposal();

  void _maybeOpenPendingProposal() {
    if (!mounted) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.activityTabIndex) {
      return;
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
      mandate: context.read<MandateSettings>(),
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
    final agents = context.watch<AgentsRepository>();
    final actions = _actions(context);
    final splitWide = MediaQuery.sizeOf(context).width >= 560;

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
    // Also include pending holds / non-actionable under history filters when
    // status filter is pending or All.
    final pendingNonActionable = [
      for (final p in proposals.proposals)
        if (p.status == TradeProposalStatus.pending &&
            (p.side == TradeProposalSide.hold || p.quantity <= 0) &&
            _matchesFilters(p))
          p,
    ];
    final historyTrades = [...history, ...pendingNonActionable];

    final pendingCount = pending.length + pendingInvestInterest.length;
    final historyCount =
        historyTrades.length + investInterestHistory.length;
    final hasPending = pendingCount > 0;
    final section = _section ??
        (hasPending
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
    final showDetailOnly = !splitWide && hasSelection;
    final hasAnyData = proposals.proposals.isNotEmpty ||
        investInterest.proposals.isNotEmpty;

    Widget detailForSelection({required bool withBack}) {
      if (selectedInvestInterest != null) {
        return _InvestInterestDetail(
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
        );
      }
      final selected = selectedTrade!;
      return _ProposalDetail(
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
      );
    }

    return MasterDetailShell<ActivityNavSection>(
      selected: section,
      sidebarBuilder: (context, highlighted, {required closeNav}) {
        final venues = actions.tradableVenues;
        return MasterDetailNavList(
          tiles: [
            for (final dest in ActivityNavSection.values)
              MasterDetailNavTile(
                title: dest.title,
                icon: dest.icon,
                meta: switch (dest) {
                  ActivityNavSection.pending => '$pendingCount',
                  ActivityNavSection.history => '$historyCount',
                },
                selected: highlighted == dest,
                onTap: () {
                  setState(() {
                    _section = dest;
                    if (!splitWide) _selectedProposalId = null;
                  });
                  closeNav();
                },
              ),
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
        );
      },
      contentBuilder: (context, selectedSection, {required onOpenMenu}) {
        if (showDetailOnly) {
          return InTabBackEffect(
            onBack: () => setState(() => _selectedProposalId = null),
            child: detailForSelection(withBack: true),
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
      roleTitle: (roleId) => _roleTitle(agents, roleId),
      portfolioLabel: (exchangeId) =>
          _portfolioLabel(actions, exchangeId),
    );

    if (!splitWide) return list;

    Widget detail;
    if (selectedInvestInterest != null) {
      detail = _InvestInterestDetail(
        proposal: selectedInvestInterest,
        events: _operationEvents(activity, selectedInvestInterest.id),
        roleTitle: _roleTitle(agents, selectedInvestInterest.roleId),
        onOpenChat: () => _openChat(
          roleId: selectedInvestInterest.roleId,
          chatId: selectedInvestInterest.chatId,
          sourceMessageId: selectedInvestInterest.sourceMessageId,
        ),
      );
    } else if (selectedTrade != null) {
      detail = _ProposalDetail(
        proposal: selectedTrade,
        events: _operationEvents(activity, selectedTrade.id),
        roleTitle: _roleTitle(agents, selectedTrade.roleId),
        portfolioLabel: _portfolioLabel(actions, selectedTrade.exchangeId),
        onOpenChat: () => _openChat(
          roleId: selectedTrade.roleId,
          chatId: selectedTrade.chatId,
          sourceMessageId: selectedTrade.sourceMessageId,
        ),
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
            _InvestInterestTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
            ),
            const SizedBox(height: 8),
          ],
          for (final p in pending) ...[
            _ProposalTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              portfolioLabel: portfolioLabel(p.exchangeId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
            ),
            const SizedBox(height: 8),
          ],
        ] else ...[
          ..._pnlRollup(context),
          for (final p in investInterestHistory) ...[
            _InvestInterestTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
            ),
            const SizedBox(height: 8),
          ],
          for (final p in history) ...[
            _ProposalTile(
              proposal: p,
              roleTitle: roleTitle(p.roleId),
              portfolioLabel: portfolioLabel(p.exchangeId),
              selected: selectedId == p.id,
              onTap: () => onSelect(p.id),
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

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.proposal,
    required this.roleTitle,
    required this.portfolioLabel,
    required this.selected,
    required this.onTap,
  });

  final TradeProposal proposal;
  final String roleTitle;
  final String portfolioLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = _relativeTime(proposal.createdAt);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.secondary : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
                style: theme.textTheme.p.copyWith(
                  color: selected
                      ? theme.colorScheme.secondaryForeground
                      : theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$roleTitle · ${proposal.status.dashboardLabel} · '
                '$portfolioLabel · $timeLabel',
                style: theme.textTheme.muted.copyWith(
                  color: selected
                      ? theme.colorScheme.secondaryForeground
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvestInterestTile extends StatelessWidget {
  const _InvestInterestTile({
    required this.proposal,
    required this.roleTitle,
    required this.selected,
    required this.onTap,
  });

  final InvestInterestProposal proposal;
  final String roleTitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = _relativeTime(proposal.createdAt);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.secondary : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                proposal.summaryLabel,
                style: theme.textTheme.p.copyWith(
                  color: selected
                      ? theme.colorScheme.secondaryForeground
                      : theme.colorScheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$roleTitle · Invest interest · '
                '${proposal.status.dashboardLabel} · $timeLabel',
                style: theme.textTheme.muted.copyWith(
                  color: selected
                      ? theme.colorScheme.secondaryForeground
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.roleTitle,
    this.portfolioLabel,
  });

  final AgentActivityEvent event;
  final String roleTitle;
  final String? portfolioLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final timeLabel = _relativeTime(event.createdAt);
    final meta = [
      event.kind.label,
      roleTitle,
      ?portfolioLabel,
      timeLabel,
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta,
              style: theme.textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (event.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(event.summary, style: theme.textTheme.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvestInterestDetail extends StatelessWidget {
  const _InvestInterestDetail({
    required this.proposal,
    required this.events,
    required this.roleTitle,
    required this.onOpenChat,
    this.onBack,
  });

  final InvestInterestProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final VoidCallback onOpenChat;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final pending =
        proposal.status == InvestInterestProposalStatus.pending;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(proposal.summaryLabel, style: theme.textTheme.h4),
        const SizedBox(height: 6),
        Text(
          '$roleTitle · Invest interest · ${proposal.status.dashboardLabel}',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 4),
        Text(
          _relativeTime(proposal.createdAt),
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
        if (proposal.add.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Add: ${proposal.add.join(', ')}', style: theme.textTheme.p),
        ],
        if (proposal.remove.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Remove: ${proposal.remove.join(', ')}',
            style: theme.textTheme.p,
          ),
        ],
        if (proposal.setSymbols != null) ...[
          const SizedBox(height: 8),
          Text(
            'Set to: ${proposal.setSymbols!.join(', ')}',
            style: theme.textTheme.p,
          ),
        ],
        if (proposal.rationale.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(proposal.rationale, style: theme.textTheme.p),
        ],
        if (proposal.applyError != null) ...[
          const SizedBox(height: 8),
          Text(
            proposal.applyError!,
            style: theme.textTheme.small.copyWith(
              color: BrandColors.lossOf(context),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ShadButton(
            onPressed: onOpenChat,
            child: Text(pending ? 'Open chat to confirm' : 'Open chat'),
          ),
        ),
        const SizedBox(height: 20),
        Text('Timeline', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text('No linked events.', style: theme.textTheme.muted)
        else
          for (final e in events) ...[
            _EventTile(event: e, roleTitle: roleTitle),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _ProposalDetail extends StatelessWidget {
  const _ProposalDetail({
    required this.proposal,
    required this.events,
    required this.roleTitle,
    required this.portfolioLabel,
    required this.onOpenChat,
    this.onBack,
  });

  final TradeProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final String portfolioLabel;
  final VoidCallback onOpenChat;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final riskColor = proposal.riskApproved
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);
    final pending = proposal.status == TradeProposalStatus.pending;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (onBack != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
          style: theme.textTheme.h4,
        ),
        const SizedBox(height: 6),
        Text(
          '$roleTitle · ${proposal.status.dashboardLabel} · $portfolioLabel',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 4),
        Text(
          _relativeTime(proposal.createdAt),
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 8),
        Text(
          proposal.riskApproved ? 'Risk approved' : 'Risk veto',
          style: theme.textTheme.small.copyWith(
            color: riskColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (proposal.rationale.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(proposal.rationale, style: theme.textTheme.p),
        ],
        if (proposal.orderId != null) ...[
          const SizedBox(height: 8),
          Text('Order: ${proposal.orderId}', style: theme.textTheme.small),
        ],
        if (proposal.executionError != null) ...[
          const SizedBox(height: 8),
          Text(
            proposal.executionError!,
            style: theme.textTheme.small.copyWith(
              color: BrandColors.lossOf(context),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ShadButton(
            onPressed: onOpenChat,
            child: Text(pending ? 'Open chat to confirm' : 'Open chat'),
          ),
        ),
        if (pending && proposal.symbol.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AgentLaunchButton(
              symbol: proposal.symbol,
              intent: AgentLaunchIntent.tradeCheck,
              exchangeId: proposal.exchangeId == 'practice'
                  ? null
                  : proposal.exchangeId,
              side: proposal.side.name,
              quantity: proposal.quantity > 0 ? proposal.quantity : null,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Timeline', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text('No linked events.', style: theme.textTheme.muted)
        else
          for (final e in events) ...[
            _EventTile(
              event: e,
              roleTitle: roleTitle,
              portfolioLabel: e.exchangeId == null
                  ? null
                  : (e.exchangeId == proposal.exchangeId
                      ? portfolioLabel
                      : e.exchangeId),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

String _relativeTime(DateTime utc) => formatRelativeTime(utc);
