import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import 'agent_chat_screen.dart';

/// Activity list + optional detail for agent runs and proposals.
class AgentActivityPane extends StatefulWidget {
  const AgentActivityPane({
    super.key,
    this.showBack = false,
    this.onBack,
  });

  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<AgentActivityPane> createState() => _AgentActivityPaneState();
}

class _AgentActivityPaneState extends State<AgentActivityPane> {
  String? _selectedProposalId;
  String? _filterRoleId;
  TradeProposalStatus? _filterStatus;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final activity = context.watch<AgentActivityRepository>();
    final proposals = context.watch<TradeProposalRepository>();
    final agents = context.watch<AgentsRepository>();
    final events = activity.events;
    final proposalList = [
      for (final p in proposals.proposals)
        if ((_filterRoleId == null || p.roleId == _filterRoleId) &&
            (_filterStatus == null || p.status == _filterStatus))
          p,
    ];

    final selected = _selectedProposalId == null
        ? null
        : proposals.byId(_selectedProposalId!);

    return MasterDetailContentPane(
      title: 'Activity',
      subtitle:
          'Suggestions and orders from connected agents (Practice or live).',
      showBack: widget.showBack,
      onBack: widget.onBack,
      backLabel: 'Agents',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final list = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All roles',
                      selected: _filterRoleId == null,
                      onTap: () => setState(() => _filterRoleId = null),
                    ),
                    for (final role in agents.availableRoles)
                      _FilterChip(
                        label: role.title,
                        selected: _filterRoleId == role.id,
                        onTap: () => setState(() => _filterRoleId = role.id),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All status',
                      selected: _filterStatus == null,
                      onTap: () => setState(() => _filterStatus = null),
                    ),
                    for (final s in TradeProposalStatus.values)
                      _FilterChip(
                        label: s.label,
                        selected: _filterStatus == s,
                        onTap: () => setState(() => _filterStatus = s),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: proposalList.isEmpty && events.isEmpty
                    ? const AppEmptyView(
                        'No agent activity yet. Connect an exchange, then '
                        'run a trading agent to see proposals here.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          if (proposalList.isNotEmpty) ...[
                            Text('Proposals', style: theme.textTheme.large),
                            const SizedBox(height: 8),
                            for (final p in proposalList) ...[
                              _ProposalTile(
                                proposal: p,
                                roleTitle: _roleTitle(agents, p.roleId),
                                selected: selected?.id == p.id,
                                onTap: () => setState(
                                  () => _selectedProposalId = p.id,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            const SizedBox(height: 12),
                          ],
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
                                roleTitle: _roleTitle(agents, e.roleId),
                                onTap: e.proposalId == null
                                    ? null
                                    : () => setState(
                                          () => _selectedProposalId =
                                              e.proposalId,
                                        ),
                              ),
                              const SizedBox(height: 6),
                            ],
                        ],
                      ),
              ),
            ],
          );

          if (!wide) {
            if (selected != null) {
              return _ProposalDetail(
                proposal: selected,
                events: activity.forProposal(selected.id),
                roleTitle: _roleTitle(agents, selected.roleId),
                onBack: () => setState(() => _selectedProposalId = null),
                onOpenChat: () => _openChat(agents, selected.roleId),
              );
            }
            return list;
          }

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
                          'Select a proposal for details.',
                          style: theme.textTheme.muted,
                        ),
                      )
                    : _ProposalDetail(
                        proposal: selected,
                        events: activity.forProposal(selected.id),
                        roleTitle: _roleTitle(agents, selected.roleId),
                        onOpenChat: () => _openChat(agents, selected.roleId),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _roleTitle(AgentsRepository agents, String roleId) {
    for (final r in agents.availableRoles) {
      if (r.id == roleId) return r.title;
    }
    return roleId;
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
      constraints: const BoxConstraints(minHeight: 36),
      child: ShadButton.raw(
        variant: selected ? ShadButtonVariant.secondary : ShadButtonVariant.outline,
        size: ShadButtonSize.sm,
        onPressed: onTap,
        child: Text(
          label,
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
    required this.selected,
    required this.onTap,
  });

  final TradeProposal proposal;
  final String roleTitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
                '$roleTitle · ${proposal.status.label} · ${proposal.exchangeId}',
                style: theme.textTheme.muted,
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
    this.onTap,
  });

  final AgentActivityEvent event;
  final String roleTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
                '${event.kind.label} · $roleTitle',
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
    required this.onOpenChat,
    this.onBack,
  });

  final TradeProposal proposal;
  final List<AgentActivityEvent> events;
  final String roleTitle;
  final VoidCallback onOpenChat;
  final VoidCallback? onBack;

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
          '$roleTitle · ${proposal.status.label} · ${proposal.exchangeId}',
          style: theme.textTheme.muted,
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
            child: const Text('Open chat'),
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
