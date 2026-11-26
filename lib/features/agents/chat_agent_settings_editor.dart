import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_agent_settings.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/models.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_option_tiles.dart';

/// Opens a scrollable dialog to edit [thread]'s per-chat Agent settings.
Future<void> showChatAgentSettingsEditor(
  BuildContext context,
  AgentChatThread thread,
) async {
  final saved = await showAppDialog<bool>(
    context: context,
    autofocusPrimaryInput: false,
    builder: (dialogContext) => _ChatAgentSettingsDialog(thread: thread),
  );
  if (saved == true && context.mounted) {
    showAppToast(
      context,
      title: 'Agent settings saved',
      description: 'Mood, specialties, and portfolio updated for this chat.',
    );
  }
}

class _ChatAgentSettingsDialog extends StatefulWidget {
  const _ChatAgentSettingsDialog({required this.thread});

  final AgentChatThread thread;

  @override
  State<_ChatAgentSettingsDialog> createState() =>
      _ChatAgentSettingsDialogState();
}

class _ChatAgentSettingsDialogState extends State<_ChatAgentSettingsDialog> {
  late ChatAgentSettings _draft;
  late final TextEditingController _noteController;
  var _saving = false;

  static final _moodOptions = [
    for (final mood in AgentAnswerMood.values) (mood, mood.label),
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.thread.agentSettings;
    _noteController = TextEditingController(
      text: _draft.answerMoodNote ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final note = AgentAppSettings.normalizeAnswerMoodNote(
        _noteController.text,
      );
      final next = _draft.copyWith(
        answerMoodNote: note,
        clearAnswerMoodNote: note == null,
      );
      await context.read<AgentChatRepository>().setAgentSettings(
            widget.thread.chatId,
            next,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setRoleEnabled(String roleId, bool enabled) {
    final disabled = Set<String>.from(_draft.disabledRoleIds);
    if (enabled) {
      disabled.remove(roleId);
    } else {
      disabled.add(roleId);
    }
    setState(() {
      _draft = _draft.copyWith(disabledRoleIds: disabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final agents = context.watch<AgentsRepository>();
    final tradeExecutor = context.watch<TradeExecutor>();
    final venues = tradeExecutor.tradableVenues;
    final portfolioLabel = _draft.autopilotExchangeId ??
        (venues.length == 1
            ? venues.first.displayName
            : 'pick on Confirm');

    return ShadDialog(
      title: const Text('Agent settings'),
      description: Text(
        'Mood, specialties, and Autopilot portfolio for '
        '“${widget.thread.title}”. Autopilot on/off and Memory stay on the '
        'chat ⋯ menu.',
        style: theme.textTheme.muted,
      ),
      actions: [
        ShadButton.outline(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Answer mood', style: theme.textTheme.large),
              const SizedBox(height: 4),
              Text(
                'How agents phrase answers in this chat.',
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 8),
              SettingsExclusiveChips<AgentAnswerMood>(
                options: _moodOptions,
                value: _draft.answerMood,
                onChanged: (mood) {
                  setState(() {
                    _draft = _draft.copyWith(answerMood: mood);
                  });
                },
                hintFor: (mood) => mood.description,
              ),
              const SizedBox(height: 10),
              Text('Optional style note', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _noteController,
                maxLength: AgentAppSettings.maxAnswerMoodNoteLength,
                placeholder: const Text(
                  'e.g. Prefer bullet lists; avoid stock-ticker slang',
                ),
              ),
              const SizedBox(height: 20),
              Text('Enabled specialties', style: theme.textTheme.large),
              const SizedBox(height: 4),
              Text(
                'Turn roles off to hide their starter prompts and keep them '
                'out of the orchestrator for this chat.',
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 8),
              for (final role in agents.availableRoles) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(role.title, style: theme.textTheme.large),
                    ),
                    ShadSwitch(
                      value: _draft.isRoleEnabled(role.id),
                      onChanged: (v) => _setRoleEnabled(role.id, v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 12),
              Text('Autopilot portfolio', style: theme.textTheme.large),
              const SizedBox(height: 4),
              Text(
                'Preferred Confirm / Autopilot target when this chat has '
                'Autopilot on. Enable Autopilot from the chat ⋯ menu.',
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 8),
              Text(
                'Portfolio: $portfolioLabel',
                style: theme.textTheme.muted,
              ),
              if (venues.isNotEmpty) ...[
                const SizedBox(height: 8),
                ShadSelect<String>(
                  minWidth: double.infinity,
                  initialValue: _draft.autopilotExchangeId,
                  placeholder: const Text('Preferred portfolio'),
                  options: [
                    for (final v in venues)
                      ShadOption(value: v.id, child: Text(v.displayName)),
                  ],
                  selectedOptionBuilder: (context, value) {
                    for (final v in venues) {
                      if (v.id == value) return Text(v.displayName);
                    }
                    return Text(value);
                  },
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _draft = _draft.copyWith(autopilotExchangeId: value);
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
