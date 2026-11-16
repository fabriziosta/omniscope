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
import '../../data/agents/agents_repository.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/tab_page_header.dart';

/// Shell tab: historical archive of agent discoveries and operations.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ShellNavigationController? _shellNav;
  String? _selectedProposalId;
  String? _filterPortfolioId;
  TradeProposalStatus? _filterStatus;

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
    setState(() => _selectedProposalId = proposalId);
  }

  TradeProposalActions _actions(BuildContext context) {
    return TradeProposalActions(
      appSettings: context.read<AgentAppSettings>(),
      proposals: context.read<TradeProposalRepository>(),
      activity: context.read<AgentActivityRepository>(),
      tradeExecutor: context.read<TradeExecutor>(),
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

  Future<void> _openChat({
    required String roleId,
    String? chatId,
    String? sourceMessageId,
  }) async {
    final chats = context.read<AgentChatRepository>();
    final shellNav = context.read<ShellNavigationController>();
    final existing = chats.findThread(
      chatId: chatId,
      sourceMessageId: sourceMessageId,
    );
    if (existing != null) {
      shellNav.goToAgentChat(
        chatId: existing.chatId,
        starterRoleId: roleId,
      );
      return;
    }
    final thread = await chats.createChat(title: roleId);
    if (!mounted) return;
    shellNav.goToAgentChat(
      chatId: thread.chatId,
      starterRoleId: roleId,
    );
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
    final events = [
      for (final e in activity.events)
        if (_filterPortfolioId == null ||
            e.exchangeId == null ||
            e.exchangeId == _filterPortfolioId)
          e,
    ];

    final selectedTrade = _selectedProposalId == null
        ? null
        : proposals.byId(_selectedProposalId!);
    final selectedInvestInterest = _selectedProposalId == null
        ? null
        : investInterest.byId(_selectedProposalId!);
    final hasSelection =
        selectedTrade != null || selectedInvestInterest != null;

    final showDetailOnly = !splitWide && hasSelection;

    Widget detailForSelection() {
      if (selectedInvestInterest != null) {
        return _InvestInterestDetail(
          proposal: selectedInvestInterest,
          events: activity.forProposal(selectedInvestInterest.id),
          roleTitle: _roleTitle(agents, selectedInvestInterest.roleId),
          onBack: showDetailOnly
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
        events: activity.forProposal(selected.id),
        roleTitle: _roleTitle(agents, selected.roleId),
        portfolioLabel: _portfolioLabel(actions, selected.exchangeId),
        onBack: showDetailOnly
            ? () => setState(() => _selectedProposalId = null)
            : null,
        onOpenChat: () => _openChat(
          roleId: selected.roleId,
          chatId: selected.chatId,
          sourceMessageId: selected.sourceMessageId,
        ),
      );
    }

    return InTabBackEffect(
      onBack: showDetailOnly
          ? () => setState(() => _selectedProposalId = null)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!showDetailOnly)
            const TabPageHeader(
              title: 'Activity',
              subtitle:
                  'Archive of agent discoveries and operations. Open a chat '
                  'to confirm pending suggestions.',
              subtitleSpacing: 6,
            ),
          Expanded(
            child: showDetailOnly
                ? detailForSelection()
                : _buildSplitOrList(
                    theme: theme,
                    agents: agents,
                    actions: actions,
                    activity: activity,
                    pending: pending,
                    pendingInvestInterest: pendingInvestInterest,
                    history: [...history, ...pendingNonActionable],
                    investInterestHistory: investInterestHistory,
                    events: events,
                    selectedId: _selectedProposalId,
                    selectedTrade: selectedTrade,
                    selectedInvestInterest: selectedInvestInterest,
                    splitWide: splitWide,
                    hasAnyData: proposals.proposals.isNotEmpty ||
                        investInterest.proposals.isNotEmpty ||
                        activity.events.isNotEmpty,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitOrList({
    required ShadThemeData theme,
    required AgentsRepository agents,
    required TradeProposalActions actions,
    required AgentActivityRepository activity,
    required List<TradeProposal> pending,
    required List<InvestInterestProposal> pendingInvestInterest,
    required List<TradeProposal> history,
    required List<InvestInterestProposal> investInterestHistory,
    required List<AgentActivityEvent> events,
    required String? selectedId,
    required TradeProposal? selectedTrade,
    required InvestInterestProposal? selectedInvestInterest,
    required bool splitWide,
    required bool hasAnyData,
  }) {
    final list = _ActivityList(
      actions: actions,
      pending: pending,
      pendingInvestInterest: pendingInvestInterest,
      history: history,
      investInterestHistory: investInterestHistory,
      events: events,
      selectedId: selectedId,
      filterPortfolioId: _filterPortfolioId,
      filterStatus: _filterStatus,
      hasAnyData: hasAnyData,
      onFilterPortfolio: (id) => setState(() => _filterPortfolioId = id),
      onFilterStatus: (s) => setState(() => _filterStatus = s),
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
        events: activity.forProposal(selectedInvestInterest.id),
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
        events: activity.forProposal(selectedTrade.id),
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
    required this.actions,
    required this.pending,
    required this.pendingInvestInterest,
    required this.history,
    required this.investInterestHistory,
    required this.events,
    required this.selectedId,
    required this.filterPortfolioId,
    required this.filterStatus,
    required this.hasAnyData,
    required this.onFilterPortfolio,
    required this.onFilterStatus,
    required this.onSelect,
    required this.roleTitle,
    required this.portfolioLabel,
  });

  final TradeProposalActions actions;
  final List<TradeProposal> pending;
  final List<InvestInterestProposal> pendingInvestInterest;
  final List<TradeProposal> history;
  final List<InvestInterestProposal> investInterestHistory;
  final List<AgentActivityEvent> events;
  final String? selectedId;
  final String? filterPortfolioId;
  final TradeProposalStatus? filterStatus;
  final bool hasAnyData;
  final ValueChanged<String?> onFilterPortfolio;
  final ValueChanged<TradeProposalStatus?> onFilterStatus;
  final ValueChanged<String> onSelect;
  final String Function(String roleId) roleTitle;
  final String Function(String exchangeId) portfolioLabel;

  static const _statusFilters = <TradeProposalStatus?>[
    null,
    TradeProposalStatus.pending,
    TradeProposalStatus.executed,
    TradeProposalStatus.dismissed,
    TradeProposalStatus.failed,
  ];

  String _statusChipLabel(TradeProposalStatus? s) {
    if (s == null) return 'All status';
    return s.dashboardLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final venues = actions.tradableVenues;

    if (!hasAnyData) {
      return const AppEmptyView(
        'No agent operations yet. Start a chat on Agents and Run a symbol — '
        'discoveries and trade history appear here.',
      );
    }

    final pendingEmpty = pending.isEmpty && pendingInvestInterest.isEmpty;
    final historyEmpty = history.isEmpty && investInterestHistory.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _statusFilters)
              _FilterChip(
                label: _statusChipLabel(s),
                selected: filterStatus == s,
                onTap: () => onFilterStatus(s),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'All portfolios',
              selected: filterPortfolioId == null,
              onTap: () => onFilterPortfolio(null),
            ),
            for (final v in venues)
              _FilterChip(
                label: v.displayName,
                selected: filterPortfolioId == v.id,
                onTap: () => onFilterPortfolio(v.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Awaiting chat confirmation',
          style: theme.textTheme.large,
        ),
        const SizedBox(height: 4),
        Text(
          'Open the chat to Confirm or Dismiss.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 8),
        if (pendingEmpty)
          Text(
            filterStatus != null &&
                    filterStatus != TradeProposalStatus.pending
                ? 'No pending ops match these filters.'
                : 'Nothing waiting for confirmation.',
            style: theme.textTheme.muted,
          )
        else ...[
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
        ],
        const SizedBox(height: 16),
        Text('History', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (historyEmpty)
          Text(
            'No past operations yet.',
            style: theme.textTheme.muted,
          )
        else ...[
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
        const SizedBox(height: 16),
        Text('Recent events', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text(
            'No events logged yet.',
            style: theme.textTheme.muted,
          )
        else
          for (final e in events.take(40)) ...[
            _EventTile(
              event: e,
              roleTitle: roleTitle(e.roleId),
              portfolioLabel: e.exchangeId == null
                  ? null
                  : portfolioLabel(e.exchangeId!),
              onTap: e.proposalId == null
                  ? null
                  : () => onSelect(e.proposalId!),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 220),
      child: ShadButton.raw(
        variant:
            selected ? ShadButtonVariant.secondary : ShadButtonVariant.outline,
        size: ShadButtonSize.sm,
        onPressed: onTap,
        // ShadButton's inner Row gives Text unbounded width; Flexible lets
        // ellipsis kick in when the chip hits maxWidth.
        child: Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small.copyWith(
              color: selected
                  ? theme.colorScheme.secondaryForeground
                  : theme.colorScheme.foreground,
            ),
          ),
        ),
      ),
    );
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
    this.onTap,
  });

  final AgentActivityEvent event;
  final String roleTitle;
  final String? portfolioLabel;
  final VoidCallback? onTap;

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
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
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
