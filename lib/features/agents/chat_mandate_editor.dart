import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/models.dart';
import '../../data/settings/mandate_settings.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_option_tiles.dart';

/// Opens a scrollable dialog to edit [thread]'s per-chat Mandate.
Future<void> showChatMandateEditor(
  BuildContext context,
  AgentChatThread thread,
) async {
  final saved = await showAppDialog<bool>(
    context: context,
    autofocusPrimaryInput: false,
    builder: (dialogContext) => _ChatMandateDialog(thread: thread),
  );
  if (saved == true && context.mounted) {
    showAppToast(
      context,
      title: 'Mandate saved',
      description: AppCopy.mandateRiskRailsSaved,
    );
  }
}

class _ChatMandateDialog extends StatefulWidget {
  const _ChatMandateDialog({required this.thread});

  final AgentChatThread thread;

  @override
  State<_ChatMandateDialog> createState() => _ChatMandateDialogState();
}

class _ChatMandateDialogState extends State<_ChatMandateDialog> {
  late ChatMandate _draft;
  late final TextEditingController _maxSymbolsController;
  late final TextEditingController _maxNotionalController;
  late final TextEditingController _maxOpenController;
  late final TextEditingController _maxFillsController;
  late final TextEditingController _maxDailyLossController;
  var _saving = false;

  static final _goalOptions = [
    for (final goal in MandateGoal.values) (goal, goal.label),
  ];

  static final _horizonOptions = [
    for (final horizon in MandateHorizon.values) (horizon, horizon.label),
  ];

  static final _universeOptions = [
    for (final universe in MandateUniverse.values) (universe, universe.label),
  ];

  static final _cadenceOptions = [
    for (final interval in AgentScheduleInterval.values)
      (interval, interval.shortLabel),
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.thread.mandate;
    _maxSymbolsController = TextEditingController(
      text: _draft.maxSymbolCount.toString(),
    );
    final notional = _draft.maxNotionalPerProposal;
    _maxNotionalController = TextEditingController(
      text: _formatOptionalMoney(notional),
    );
    _maxOpenController = TextEditingController(
      text: _draft.maxOpenProposals.toString(),
    );
    _maxFillsController = TextEditingController(
      text: _draft.maxAutopilotFillsPerDay.toString(),
    );
    _maxDailyLossController = TextEditingController(
      text: _formatOptionalMoney(_draft.maxDailyRealizedLoss),
    );
  }

  static String _formatOptionalMoney(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _maxSymbolsController.dispose();
    _maxNotionalController.dispose();
    _maxOpenController.dispose();
    _maxFillsController.dispose();
    _maxDailyLossController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final maxSymbols = int.tryParse(_maxSymbolsController.text.trim());
    if (maxSymbols == null || maxSymbols < ChatMandate.minSymbolCount) {
      showAppToast(
        context,
        description:
            'Max symbols must be at least ${ChatMandate.minSymbolCount}.',
        destructive: true,
      );
      return;
    }
    final maxOpen = int.tryParse(_maxOpenController.text.trim());
    if (maxOpen == null || maxOpen < ChatMandate.minOpenProposals) {
      showAppToast(
        context,
        description:
            'Max open proposals must be at least '
            '${ChatMandate.minOpenProposals}.',
        destructive: true,
      );
      return;
    }
    final maxFills = int.tryParse(_maxFillsController.text.trim());
    if (maxFills == null ||
        maxFills < ChatMandate.minAutopilotFillsPerDay) {
      showAppToast(
        context,
        description:
            'Max Autopilot fills/day must be at least '
            '${ChatMandate.minAutopilotFillsPerDay}.',
        destructive: true,
      );
      return;
    }
    final notionalRaw = _maxNotionalController.text.trim().replaceAll(',', '');
    double? notional;
    if (notionalRaw.isNotEmpty) {
      notional = double.tryParse(notionalRaw);
      if (notional == null || notional <= 0) {
        showAppToast(
          context,
          description:
              'Max notional must be a positive dollar amount, or empty.',
          destructive: true,
        );
        return;
      }
    }
    final lossRaw = _maxDailyLossController.text.trim().replaceAll(',', '');
    double? dailyLoss;
    if (lossRaw.isNotEmpty) {
      dailyLoss = double.tryParse(lossRaw);
      if (dailyLoss == null || dailyLoss <= 0) {
        showAppToast(
          context,
          description:
              'Max daily loss must be a positive dollar amount, or empty.',
          destructive: true,
        );
        return;
      }
    }

    final next = ChatMandate(
      goal: _draft.goal,
      horizon: _draft.horizon,
      universe: _draft.universe,
      cadencePreference: _draft.cadencePreference,
      maxSymbolCount: maxSymbols.clamp(
        ChatMandate.minSymbolCount,
        ChatMandate.maxSymbolCountCap,
      ),
      maxOpenProposals: maxOpen.clamp(
        ChatMandate.minOpenProposals,
        ChatMandate.maxOpenProposalsCap,
      ),
      maxAutopilotFillsPerDay: maxFills.clamp(
        ChatMandate.minAutopilotFillsPerDay,
        ChatMandate.maxAutopilotFillsPerDayCap,
      ),
      maxNotionalPerProposal: notional,
      maxDailyRealizedLoss: dailyLoss,
    );

    setState(() => _saving = true);
    await context.read<AgentChatRepository>().setMandate(
          widget.thread.chatId,
          next,
        );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ShadDialog(
      title: const Text('Chat Mandate'),
      description: Text(AppCopy.mandateIntro),
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
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSubsectionLabel(
                'Goal',
                description: 'What agents should optimize for in this chat.',
              ),
              const SizedBox(height: 8),
              SettingsExclusiveChips<MandateGoal>(
                options: _goalOptions,
                value: _draft.goal,
                onChanged: (goal) => setState(
                  () => _draft = _draft.copyWith(goal: goal),
                ),
                hintFor: (goal) => goal.description,
              ),
              const SizedBox(height: settingsSectionGap),
              SettingsSubsectionLabel(
                'Horizon',
                description: 'How far ahead agents should think.',
              ),
              const SizedBox(height: 8),
              SettingsExclusiveChips<MandateHorizon>(
                options: _horizonOptions,
                value: _draft.horizon,
                onChanged: (horizon) => setState(
                  () => _draft = _draft.copyWith(horizon: horizon),
                ),
                hintFor: (horizon) => horizon.description,
              ),
              const SizedBox(height: settingsSectionGap),
              SettingsSubsectionLabel(
                'Universe',
                description: 'Which assets agents may put in Invest interest.',
              ),
              const SizedBox(height: 8),
              SettingsExclusiveChips<MandateUniverse>(
                options: _universeOptions,
                value: _draft.universe,
                onChanged: (universe) => setState(
                  () => _draft = _draft.copyWith(universe: universe),
                ),
                hintFor: (universe) => universe.description,
              ),
              const SizedBox(height: settingsSectionGap),
              SettingsSubsectionLabel(
                'Preferred cadence',
                description:
                    'Suggested schedule interval for agents. Does not change '
                    'Settings → Agents Schedule timing.',
              ),
              const SizedBox(height: 8),
              SettingsExclusiveChips<AgentScheduleInterval>(
                options: _cadenceOptions,
                value: _draft.cadencePreference,
                onChanged: (interval) => setState(
                  () => _draft = _draft.copyWith(cadencePreference: interval),
                ),
                hintFor: (interval) =>
                    'About every ${interval.label.toLowerCase()}',
              ),
              const SizedBox(height: settingsSectionGap),
              SettingsSubsectionLabel(
                'Risk rails',
                description:
                    'Hard caps for Invest interest size, Autopilot fills per '
                    'day (UTC, this chat), optional daily loss stop, and max '
                    'notional per order.',
              ),
              const SizedBox(height: 8),
              SettingsWidePair(
                first: SettingsLabeledInput(
                  label: 'Max invest-interest symbols',
                  controller: _maxSymbolsController,
                  keyboardType: TextInputType.number,
                  placeholder: const Text('20'),
                ),
                second: SettingsLabeledInput(
                  label: 'Max open Autopilot proposals',
                  controller: _maxOpenController,
                  keyboardType: TextInputType.number,
                  placeholder: const Text('3'),
                ),
              ),
              const SizedBox(height: 8),
              SettingsWidePair(
                first: SettingsLabeledInput(
                  label: 'Max Autopilot fills per day',
                  controller: _maxFillsController,
                  keyboardType: TextInputType.number,
                  placeholder: const Text('10'),
                ),
                second: SettingsLabeledInput(
                  label: 'Max daily realized loss (optional)',
                  controller: _maxDailyLossController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  placeholder: const Text('Leave empty for no stop'),
                ),
              ),
              const SizedBox(height: 8),
              SettingsLabeledInput(
                label: 'Max notional per proposal (optional, enforced)',
                controller: _maxNotionalController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                placeholder: const Text('Leave empty for no cap'),
              ),
              const SizedBox(height: 4),
              Text(
                AppCopy.mandateRiskRailsSaved,
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
