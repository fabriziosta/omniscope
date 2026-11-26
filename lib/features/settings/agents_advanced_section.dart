import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_memory.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/models.dart';
import '../../data/agents/schedule_chat_binding.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

/// Settings → Agents: shared memory, Schedule, and local clear/reset actions
/// (mood / specialties / portfolio are per-chat under Agents list / chat ⋯).
class AgentsAdvancedSectionBody extends StatelessWidget {
  const AgentsAdvancedSectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by subsection id.
  final Map<String, GlobalKey>? subsectionKeys;

  static final _intervalOptions = [
    for (final interval in AgentScheduleInterval.values)
      (interval, interval.shortLabel),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final app = context.watch<AgentAppSettings>();
    final favorites = context.watch<FavoritesRepository>();
    final memory = context.watch<AgentMemoryRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Shared memory and Schedule are device-wide. Answer mood, '
          'specialties, Autopilot portfolio, and Mandate are edited per chat '
          '(Agents list or chat title ⋯).',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Shared memory',
          key: subsectionKeys?['sharedMemory'],
          description:
              'Durable facts shared across chats that have Memory on '
              '(default). Agents may remember/forget during Runs; you can '
              'edit here. Turn Memory off per chat from the chat options '
              'menu (list row or chat title ⋯).',
        ),
        const SizedBox(height: 8),
        _SharedMemoryEditor(memory: memory),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Schedule',
          key: subsectionKeys?['schedule'],
          description:
              'While Omniscope is open, periodically Run research on Invest '
              'interest (or typed symbols) into one pinned Schedule chat. '
              'Deleting that chat stops Schedule. Confirm still gates fills; '
              'turn on Autopilot on the chat to auto-apply there.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Enable schedule', style: theme.textTheme.large),
            ),
            ShadSwitch(
              value: app.scheduleEnabled,
              onChanged: (v) async {
                if (v) {
                  final chats = context.read<AgentChatRepository>();
                  await app.setSchedule(enabled: true);
                  await ScheduleChatBinding.ensureChat(
                    app: app,
                    chats: chats,
                  );
                  if (!context.mounted) return;
                  showAppToast(
                    context,
                    description:
                        'Schedule on — results go to the Scheduled run chat',
                  );
                } else {
                  await app.setSchedule(enabled: false);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Interval', style: theme.textTheme.small),
        const SizedBox(height: 6),
        SettingsExclusiveChips<AgentScheduleInterval>(
          options: _intervalOptions,
          value: app.scheduleInterval,
          onChanged: (interval) => app.setSchedule(
            enabled: app.scheduleEnabled,
            interval: interval,
          ),
          hintFor: (interval) =>
              'About every ${interval.label.toLowerCase()}',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Use Markets → Invest interest '
                '(${favorites.investInterestSymbols.length} symbols)',
                style: theme.textTheme.large,
              ),
            ),
            ShadSwitch(
              value: app.scheduleUseInvestInterest,
              onChanged: (v) => app.setSchedule(
                enabled: app.scheduleEnabled,
                useInvestInterest: v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SettingsSubsectionLabel(
          'Agent chats',
          key: subsectionKeys?['agentChats'],
          description:
              'Deletes every saved agent conversation on this device. '
              'API keys and Schedule prefs are kept until you reset them.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _clearChats(context),
            child: const Text('Clear all agent chats'),
          ),
        ),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Trade activity',
          key: subsectionKeys?['tradeActivity'],
          description:
              'Removes proposals, the Activity timeline, and Alerts. '
              'Chat history is kept.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _clearTradeActivity(context),
            child: const Text('Clear proposals and activity'),
          ),
        ),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Agent prefs',
          description:
              'Resets Schedule, shared Autopilot defaults, and legacy role '
              'overrides. LLM keys and chat history are kept.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _resetAgentPrefs(context),
            child: const Text('Reset agent prefs'),
          ),
        ),
      ],
    );
  }
}

Future<void> _clearChats(BuildContext context) async {
  final ok = await confirmDestructiveAction(
    context,
    title: 'Clear all agent chats?',
    description:
        'Deletes every saved agent conversation on this device. '
        'Agent connections and API keys are kept. This cannot be undone.',
    confirmLabel: 'Clear chats',
  );
  if (!ok || !context.mounted) return;
  final hadSchedule = context.read<AgentAppSettings>().scheduleEnabled ||
      context.read<AgentAppSettings>().scheduleChatId != null;
  await context.read<AgentChatRepository>().clearAllThreads();
  if (!context.mounted) return;
  showAppToast(
    context,
    title: 'Chats cleared',
    description: hadSchedule
        ? 'All agent conversations were removed. Schedule was stopped.'
        : 'All agent conversations were removed from this device.',
  );
}

Future<void> _clearTradeActivity(BuildContext context) async {
  final ok = await confirmDestructiveAction(
    context,
    title: 'Clear proposals and activity?',
    description:
        'Removes saved agent trade and Invest interest proposals, the '
        'Activity tab timeline, and Activity Alerts on this device. '
        'Chat history is kept. This cannot be undone.',
    confirmLabel: 'Clear activity',
  );
  if (!ok || !context.mounted) return;
  final proposals = context.read<TradeProposalRepository>();
  final investInterest = context.read<InvestInterestProposalRepository>();
  final activity = context.read<AgentActivityRepository>();
  final notifications = context.read<AppNotificationRepository>();
  await proposals.clearAll();
  await investInterest.clearAll();
  await activity.clearAll();
  await notifications.clearAll();
  if (!context.mounted) return;
  showAppToast(
    context,
    title: 'Activity cleared',
    description: 'Proposals, agent activity, and alerts were removed.',
  );
}

Future<void> _resetAgentPrefs(BuildContext context) async {
  final ok = await confirmDestructiveAction(
    context,
    title: 'Reset agent prefs?',
    description:
        'Clears Schedule, Autopilot defaults, and role overrides on this '
        'device. LLM API keys and chat history are kept. This cannot be '
        'undone.',
    confirmLabel: 'Reset',
  );
  if (!ok || !context.mounted) return;
  final agentApp = context.read<AgentAppSettings>();
  final agents = context.read<AgentsRepository>();
  await agentApp.resetToDefaults();
  await agents.clearAllConnections();
  if (!context.mounted) return;
  showAppToast(
    context,
    title: 'Agent prefs reset',
    description: 'Schedule and agent settings were cleared on this device.',
  );
}

class _SharedMemoryEditor extends StatefulWidget {
  const _SharedMemoryEditor({required this.memory});

  final AgentMemoryRepository memory;

  @override
  State<_SharedMemoryEditor> createState() => _SharedMemoryEditorState();
}

class _SharedMemoryEditorState extends State<_SharedMemoryEditor> {
  late final TextEditingController _controller;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_saving) return;
    final text = _controller.text;
    setState(() => _saving = true);
    try {
      final fact = await widget.memory.addFact(
        text,
        source: AgentMemorySource.user,
      );
      if (!mounted) return;
      if (fact == null) {
        showAppToast(
          context,
          description:
              'Enter a short fact (max ${AgentMemoryRepository.maxFactLength} '
              'characters).',
          destructive: true,
        );
        return;
      }
      _controller.clear();
      showAppToast(context, description: 'Fact added to shared memory');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearAll() async {
    final count = widget.memory.facts.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear shared memory?',
      description: count == 0
          ? 'Removes every shared memory fact. This cannot be undone.'
          : 'Removes $count shared memory '
              '${count == 1 ? 'fact' : 'facts'}. This cannot be undone.',
      confirmLabel: 'Clear memory',
    );
    if (!ok || !mounted) return;
    await widget.memory.clearAll();
    if (!mounted) return;
    showAppToast(context, description: 'Shared memory cleared');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final facts = widget.memory.facts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (facts.isEmpty)
          Text(
            'No facts yet. Add one below or let agents remember during a Run.',
            style: theme.textTheme.muted,
          )
        else
          for (final fact in facts) ...[
            _MemoryFactRow(
              fact: fact,
              onDelete: () => widget.memory.removeFact(fact.id),
            ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 8),
        ShadInput(
          controller: _controller,
          maxLength: AgentMemoryRepository.maxFactLength,
          placeholder: const Text(
            'e.g. Prefer ETFs; avoid leveraged products',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton(
              size: ShadButtonSize.sm,
              onPressed: _saving ? null : _add,
              child: Text(_saving ? 'Adding…' : 'Add fact'),
            ),
            if (facts.isNotEmpty)
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _clearAll,
                child: const Text('Clear all'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${facts.length} / ${AgentMemoryRepository.maxFacts} facts',
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _MemoryFactRow extends StatelessWidget {
  const _MemoryFactRow({
    required this.fact,
    required this.onDelete,
  });

  final AgentMemoryFact fact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: theme.radius,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fact.text, style: theme.textTheme.small),
                  const SizedBox(height: 4),
                  ShadBadge.secondary(
                    child: Text(fact.source.label),
                  ),
                ],
              ),
            ),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              width: 36,
              height: 36,
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              child: Icon(
                LucideIcons.trash2,
                size: 16,
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
