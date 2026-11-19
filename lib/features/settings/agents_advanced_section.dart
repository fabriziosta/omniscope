import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../data/agents/schedule_chat_binding.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

/// Settings → Agents (advanced): mood, role enable, Autopilot, Schedule.
class AgentsAdvancedSectionBody extends StatelessWidget {
  const AgentsAdvancedSectionBody({super.key});

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
        const SettingsSubsectionLabel(
          'Answer mood',
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
        const SettingsSubsectionLabel(
          'Enabled specialties',
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
        const SettingsSubsectionLabel(
          'Autopilot portfolio',
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
        const SettingsSubsectionLabel(
          'Schedule',
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
                  await app.setSchedule(enabled: true);
                  final chats = context.read<AgentChatRepository>();
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
