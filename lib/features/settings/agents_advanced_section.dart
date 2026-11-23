import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_memory.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../data/agents/schedule_chat_binding.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

/// Settings → Agents (advanced): mood, role enable, Autopilot, Schedule.
class AgentsAdvancedSectionBody extends StatelessWidget {
  const AgentsAdvancedSectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by subsection id.
  final Map<String, GlobalKey>? subsectionKeys;

  static final _moodOptions = [
    for (final mood in AgentAnswerMood.values) (mood, mood.label),
  ];

  static final _intervalOptions = [
    for (final interval in AgentScheduleInterval.values)
      (interval, interval.shortLabel),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final agents = context.watch<AgentsRepository>();
    final app = context.watch<AgentAppSettings>();
    final favorites = context.watch<FavoritesRepository>();
    final memory = context.watch<AgentMemoryRepository>();
    final tradeExecutor = context.watch<TradeExecutor>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Power-user controls. Everyday chat uses Settings → Connections '
          'LLM keys; specialists are chosen automatically.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Shared memory',
          key: subsectionKeys?['sharedMemory'],
          description:
              'Durable facts shared across chats that have Memory on '
              '(default). Agents may remember/forget during Runs; you can '
              'edit here. Turn Memory off per chat from the Agents list or '
              'chat header.',
        ),
        const SizedBox(height: 8),
        _SharedMemoryEditor(memory: memory),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Answer mood',
          key: subsectionKeys?['answerMood'],
          description:
              'How agents phrase answers. Does not change Mandate risk rails.',
        ),
        const SizedBox(height: 8),
        SettingsExclusiveChips<AgentAnswerMood>(
          options: _moodOptions,
          value: app.answerMood,
          onChanged: app.setAnswerMood,
          hintFor: (mood) => mood.description,
        ),
        const SizedBox(height: 10),
        Text('Optional style note', style: theme.textTheme.small),
        const SizedBox(height: 6),
        _AnswerMoodNoteField(
          initialNote: app.answerMoodNote ?? '',
          onSave: app.setAnswerMoodNote,
        ),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Enabled specialties',
          key: subsectionKeys?['specialties'],
          description:
              'Turn roles off to hide their starter prompts and keep them '
              'out of the orchestrator.',
        ),
        const SizedBox(height: 8),
        for (final role in agents.availableRoles) ...[
          _RoleEnableRow(
            title: role.title,
            enabled: app.isRoleEnabled(role.id),
            onChanged: (v) => app.setRoleEnabled(role.id, v),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Autopilot portfolio',
          key: subsectionKeys?['autopilotPortfolio'],
          description:
              'Default target when a chat has Autopilot on (risk-approved '
              'trades auto-submit; investigation may auto-add Invest interest). '
              'Enable Autopilot per chat from the Agents list or chat header. '
              'Notional and daily fill/loss rails live under Settings → Mandate.',
        ),
        const SizedBox(height: 8),
        Text(
          'Default portfolio: '
          '${app.autopilotExchangeId ?? (tradeExecutor.tradableVenues.length == 1 ? tradeExecutor.tradableVenues.first.displayName : 'pick on Confirm')}',
          style: theme.textTheme.muted,
        ),
        if (tradeExecutor.tradableVenues.isNotEmpty) ...[
          const SizedBox(height: 8),
          ShadSelect<String>(
            minWidth: double.infinity,
            initialValue: app.autopilotExchangeId,
            placeholder: const Text('Default portfolio'),
            options: [
              for (final v in tradeExecutor.tradableVenues)
                ShadOption(value: v.id, child: Text(v.displayName)),
            ],
            selectedOptionBuilder: (context, value) {
              for (final v in tradeExecutor.tradableVenues) {
                if (v.id == value) return Text(v.displayName);
              }
              return Text(value);
            },
            onChanged: (value) async {
              if (value == null) return;
              await app.setAutopilot(
                enabled: app.autopilotEnabled,
                exchangeId: value,
              );
            },
          ),
        ],
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
      ],
    );
  }
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

class _AnswerMoodNoteField extends StatefulWidget {
  const _AnswerMoodNoteField({
    required this.initialNote,
    required this.onSave,
  });

  final String initialNote;
  final Future<void> Function(String? note) onSave;

  @override
  State<_AnswerMoodNoteField> createState() => _AnswerMoodNoteFieldState();
}

class _AnswerMoodNoteFieldState extends State<_AnswerMoodNoteField> {
  late final TextEditingController _controller;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void didUpdateWidget(covariant _AnswerMoodNoteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialNote != widget.initialNote &&
        _controller.text != widget.initialNote) {
      _controller.text = widget.initialNote;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text);
      if (!mounted) return;
      showAppToast(context, description: 'Answer mood note saved');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          controller: _controller,
          maxLength: AgentAppSettings.maxAnswerMoodNoteLength,
          placeholder: const Text(
            'e.g. Prefer bullet lists; avoid stock-ticker slang',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton(
            size: ShadButtonSize.sm,
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save note'),
          ),
        ),
      ],
    );
  }
}

class _RoleEnableRow extends StatelessWidget {
  const _RoleEnableRow({
    required this.title,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.large)),
        ShadSwitch(value: enabled, onChanged: onChanged),
      ],
    );
  }
}
