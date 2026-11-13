import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/portfolio_picker_dialog.dart';
import '../../widgets/tab_page_header.dart';
import '../agents/agent_chat_screen.dart';

/// Shell tab: pending confirmations + accepted/refused history with portfolio.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ShellNavigationController? _shellNav;
  String? _selectedProposalId;
  String? _filterRoleId;
  String? _filterPortfolioId;
  TradeProposalStatus? _filterStatus;
  var _acting = false;

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
      agents: context.read<AgentsRepository>(),
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

  void _openChat(AgentsRepository agents, String roleId) {
    AgentRoleDefinition? role;
    for (final r in agents.availableRoles) {
      if (r.id == roleId) {
        role = r;
        break;
      }
    }
    if (role == null) return;
    pushFadePage(context, AgentChatScreen(role: role));
  }

  Future<void> _confirmProposal(TradeProposal proposal) async {
    final actions = _actions(context);
    String? targetId = actions.resolveConfirmPortfolioId(
      roleId: proposal.roleId,
    );
    if (targetId == null) {
      targetId = await showPortfolioPickerDialog(
        context,
        venues: actions.tradableVenues,
      );
      if (targetId == null || !mounted) return;
    }
    setState(() => _acting = true);
    final err = await actions.confirm(
      proposal.id,
      targetPortfolioId: targetId,
    );
    if (!mounted) return;
    setState(() => _acting = false);
    final label = actions.portfolioDisplayName(targetId);
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    } else {
      showAppToast(
        context,
        description: 'Submitted to $label for ${proposal.symbol}',
      );
    }
  }

  Future<void> _dismissProposal(TradeProposal proposal) async {
    setState(() => _acting = true);
    final err = await _actions(context).dismiss(proposal.id);
    if (!mounted) return;
    setState(() => _acting = false);
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    }
  }

  bool _matchesFilters(TradeProposal p) {
    if (_filterRoleId != null && p.roleId != _filterRoleId) return false;
    if (_filterPortfolioId != null && p.exchangeId != _filterPortfolioId) {
      return false;
    }
    if (_filterStatus != null && p.status != _filterStatus) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final activity = context.watch<AgentActivityRepository>();
    final proposals = context.watch<TradeProposalRepository>();
    final agents = context.watch<AgentsRepository>();
    final actions = _actions(context);
    final splitWide = MediaQuery.sizeOf(context).width >= 560;

    final pending = [
      for (final p in proposals.pendingActionable)
        if (_matchesFilters(p)) p,
    ];
    final history = [
      for (final p in proposals.proposals)
        if (p.status != TradeProposalStatus.pending && _matchesFilters(p)) p,
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
        if ((_filterRoleId == null || e.roleId == _filterRoleId) &&
            (_filterPortfolioId == null ||
                e.exchangeId == null ||
                e.exchangeId == _filterPortfolioId))
          e,
    ];

    final selected = _selectedProposalId == null
        ? null
        : proposals.byId(_selectedProposalId!);

    final showDetailOnly = !splitWide && selected != null;

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
                  'Confirm pending agent suggestions and review accepted or '
                  'refused operations by portfolio.',
              subtitleSpacing: 6,
            ),
          Expanded(
            child: showDetailOnly
                ? _ProposalDetail(
                    proposal: selected,
                    events: activity.forProposal(selected.id),
                    roleTitle: _roleTitle(agents, selected.roleId),
                    portfolioLabel:
                        _portfolioLabel(actions, selected.exchangeId),
                    busy: _acting,
                    onBack: () =>
                        setState(() => _selectedProposalId = null),
                    onOpenChat: () =>
                        _openChat(agents, selected.roleId),
                    onConfirm: selected.status == TradeProposalStatus.pending &&
                            selected.side != TradeProposalSide.hold
                        ? () => _confirmProposal(selected)
                        : null,
                    onDismiss:
                        selected.status == TradeProposalStatus.pending
                            ? () => _dismissProposal(selected)
                            : null,
                  )
                : _buildSplitOrList(
                    theme: theme,
                    agents: agents,
                    actions: actions,
                    activity: activity,
                    pending: pending,
                    history: [...history, ...pendingNonActionable],
                    events: events,
                    selected: selected,
                    splitWide: splitWide,
                    hasAnyData: proposals.proposals.isNotEmpty ||
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
    required List<TradeProposal> history,
    required List<AgentActivityEvent> events,
    required TradeProposal? selected,
    required bool splitWide,
    required bool hasAnyData,
  }) {
    final list = _ActivityList(
      agents: agents,
      actions: actions,
      pending: pending,
      history: history,
      events: events,
      selectedId: selected?.id,
      filterRoleId: _filterRoleId,
      filterPortfolioId: _filterPortfolioId,
      filterStatus: _filterStatus,
      hasAnyData: hasAnyData,
      onFilterRole: (id) => setState(() => _filterRoleId = id),
      onFilterPortfolio: (id) => setState(() => _filterPortfolioId = id),
      onFilterStatus: (s) => setState(() => _filterStatus = s),
      onSelect: (id) => setState(() => _selectedProposalId = id),
      roleTitle: (roleId) => _roleTitle(agents, roleId),
      portfolioLabel: (exchangeId) =>
          _portfolioLabel(actions, exchangeId),
    );

    if (!splitWide) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: list),
        Container(width: 1, color: theme.colorScheme.border),
        Expanded(
          flex: 4,
          child: selected == null
              ? Center(
                  child: Text(
                    'Select an operation for details.',
                    style: theme.textTheme.muted,
                  ),
                )
              : _ProposalDetail(
                  proposal: selected,
                  events: activity.forProposal(selected.id),
                  roleTitle: _roleTitle(agents, selected.roleId),
                  portfolioLabel:
                      _portfolioLabel(actions, selected.exchangeId),
                  busy: _acting,
                  onOpenChat: () =>
                      _openChat(agents, selected.roleId),
                  onConfirm: selected.status == TradeProposalStatus.pending &&
                          selected.side != TradeProposalSide.hold
                      ? () => _confirmProposal(selected)
                      : null,
                  onDismiss: selected.status == TradeProposalStatus.pending
                      ? () => _dismissProposal(selected)
                      : null,
                ),
        ),
      ],
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.agents,
    required this.actions,
    required this.pending,
    required this.history,
    required this.events,
    required this.selectedId,
    required this.filterRoleId,
    required this.filterPortfolioId,
    required this.filterStatus,
    required this.hasAnyData,
    required this.onFilterRole,
    required this.onFilterPortfolio,
    required this.onFilterStatus,
    required this.onSelect,
    required this.roleTitle,
    required this.portfolioLabel,
  });

  final AgentsRepository agents;
  final TradeProposalActions actions;
  final List<TradeProposal> pending;
  final List<TradeProposal> history;
  final List<AgentActivityEvent> events;
  final String? selectedId;
  final String? filterRoleId;
  final String? filterPortfolioId;
  final TradeProposalStatus? filterStatus;
  final bool hasAnyData;
  final ValueChanged<String?> onFilterRole;
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
        'No agent operations yet. Connect a trading agent, then '
        'Run a symbol — pending suggestions appear here to confirm.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'All roles',
              selected: filterRoleId == null,
              onTap: () => onFilterRole(null),
            ),
            for (final role in agents.availableRoles)
              _FilterChip(
                label: role.title,
                selected: filterRoleId == role.id,
                onTap: () => onFilterRole(role.id),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
          'Needs confirmation',
          style: theme.textTheme.large,
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          Text(
            filterStatus != null &&
                    filterStatus != TradeProposalStatus.pending
                ? 'No pending ops match these filters.'
                : 'Nothing waiting for Confirm.',
            style: theme.textTheme.muted,
          )
        else
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
        const SizedBox(height: 16),
        Text('History', style: theme.textTheme.large),
        const SizedBox(height: 8),
        if (history.isEmpty)
          Text(
            'No past operations yet.',
            style: theme.textTheme.muted,
          )
        else
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

class _ProposalDetail extends StatelessWidget {
  const _ProposalDetail({
    required this.proposal,
    required this.events,
    required this.roleTitle,
    required this.portfolioLabel,
    required this.onOpenChat,
    this.onBack,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final TradeProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final String portfolioLabel;
  final VoidCallback onOpenChat;
  final VoidCallback? onBack;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final riskColor = proposal.riskApproved
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);

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
        if (onConfirm != null || onDismiss != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (onDismiss != null)
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ShadButton.outline(
                      enabled: !busy,
                      onPressed: onDismiss,
                      child: const Text('Dismiss'),
                    ),
                  ),
                ),
              if (onConfirm != null && onDismiss != null)
                const SizedBox(width: 8),
              if (onConfirm != null)
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ShadButton(
                      enabled: !busy,
                      onPressed: onConfirm,
                      child: const Text('Confirm'),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ShadButton.outline(
            onPressed: onOpenChat,
            child: const Text('Open chat'),
          ),
        ),
        if (proposal.status == TradeProposalStatus.pending &&
            proposal.symbol.isNotEmpty) ...[
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

String _relativeTime(DateTime utc) {
  final local = utc.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
