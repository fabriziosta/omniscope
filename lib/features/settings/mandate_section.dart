import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../data/agents/models.dart';
import '../../data/settings/mandate_settings.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

/// Settings → Mandate: user policy agents must respect.
class MandateSectionBody extends StatefulWidget {
  const MandateSectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by subsection id.
  final Map<String, GlobalKey>? subsectionKeys;

  @override
  State<MandateSectionBody> createState() => _MandateSectionBodyState();
}

class _MandateSectionBodyState extends State<MandateSectionBody> {
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
    final mandate = context.read<MandateSettings>();
    _maxSymbolsController = TextEditingController(
      text: mandate.maxSymbolCount.toString(),
    );
    final notional = mandate.maxNotionalPerProposal;
    _maxNotionalController = TextEditingController(
      text: notional == null
          ? ''
          : (notional == notional.roundToDouble()
              ? notional.toInt().toString()
              : notional.toStringAsFixed(2)),
    );
    _maxOpenController = TextEditingController(
      text: mandate.maxOpenProposals.toString(),
    );
    _maxFillsController = TextEditingController(
      text: mandate.maxAutopilotFillsPerDay.toString(),
    );
    final dailyLoss = mandate.maxDailyRealizedLoss;
    _maxDailyLossController = TextEditingController(
      text: dailyLoss == null
          ? ''
          : (dailyLoss == dailyLoss.roundToDouble()
              ? dailyLoss.toInt().toString()
              : dailyLoss.toStringAsFixed(2)),
    );
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

  Future<void> _saveRiskRails(MandateSettings mandate) async {
    final maxSymbols = int.tryParse(_maxSymbolsController.text.trim());
    if (maxSymbols == null || maxSymbols < MandateSettings.minSymbolCount) {
      showAppToast(
        context,
        description:
            'Max symbols must be at least ${MandateSettings.minSymbolCount}.',
        destructive: true,
      );
      return;
    }
    final maxOpen = int.tryParse(_maxOpenController.text.trim());
    if (maxOpen == null || maxOpen < MandateSettings.minOpenProposals) {
      showAppToast(
        context,
        description:
            'Max open proposals must be at least '
            '${MandateSettings.minOpenProposals}.',
        destructive: true,
      );
      return;
    }
    final maxFills = int.tryParse(_maxFillsController.text.trim());
    if (maxFills == null ||
        maxFills < MandateSettings.minAutopilotFillsPerDay) {
      showAppToast(
        context,
        description:
            'Max Autopilot fills/day must be at least '
            '${MandateSettings.minAutopilotFillsPerDay}.',
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
          description: 'Max notional must be a positive dollar amount, or empty.',
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

    setState(() => _saving = true);
    await mandate.setMaxSymbolCount(maxSymbols);
    await mandate.setMaxOpenProposals(maxOpen);
    await mandate.setMaxNotionalPerProposal(notional);
    await mandate.setMaxAutopilotFillsPerDay(maxFills);
    await mandate.setMaxDailyRealizedLoss(dailyLoss);
    if (!mounted) return;
    setState(() => _saving = false);
    _maxSymbolsController.text = mandate.maxSymbolCount.toString();
    _maxOpenController.text = mandate.maxOpenProposals.toString();
    _maxFillsController.text = mandate.maxAutopilotFillsPerDay.toString();
    final saved = mandate.maxNotionalPerProposal;
    _maxNotionalController.text = saved == null
        ? ''
        : (saved == saved.roundToDouble()
            ? saved.toInt().toString()
            : saved.toStringAsFixed(2));
    final savedLoss = mandate.maxDailyRealizedLoss;
    _maxDailyLossController.text = savedLoss == null
        ? ''
        : (savedLoss == savedLoss.roundToDouble()
            ? savedLoss.toInt().toString()
            : savedLoss.toStringAsFixed(2));
    showAppToast(
      context,
      title: 'Risk rails saved',
      description: AppCopy.mandateRiskRailsSaved,
    );
  }

  Widget _riskRailsFields(MandateSettings mandate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: const Text('Leave empty for no stop'),
          ),
        ),
        const SizedBox(height: 8),
        SettingsLabeledInput(
          label: 'Max notional per proposal (optional, enforced)',
          controller: _maxNotionalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          placeholder: const Text('Leave empty for no cap'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton(
            onPressed: _saving ? null : () => _saveRiskRails(mandate),
            child: Text(_saving ? 'Saving…' : 'Save risk rails'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mandate = context.watch<MandateSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppCopy.mandateIntro,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Goal',
          key: widget.subsectionKeys?['goal'],
          description: 'What agents should optimize for.',
        ),
        const SizedBox(height: 8),
        SettingsExclusiveChips<MandateGoal>(
          options: _goalOptions,
          value: mandate.goal,
          onChanged: mandate.setGoal,
          hintFor: (goal) => goal.description,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Horizon',
          key: widget.subsectionKeys?['horizon'],
          description: 'How far ahead agents should think.',
        ),
        const SizedBox(height: 8),
        SettingsExclusiveChips<MandateHorizon>(
          options: _horizonOptions,
          value: mandate.horizon,
          onChanged: mandate.setHorizon,
          hintFor: (horizon) => horizon.description,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Universe',
          key: widget.subsectionKeys?['universe'],
          description: 'Which assets agents may put in Invest interest.',
        ),
        const SizedBox(height: 8),
        SettingsExclusiveChips<MandateUniverse>(
          options: _universeOptions,
          value: mandate.universe,
          onChanged: mandate.setUniverse,
          hintFor: (universe) => universe.description,
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Preferred cadence',
          key: widget.subsectionKeys?['cadence'],
          description:
              'Suggested schedule interval when connecting agents. '
              'Does not change existing connections.',
        ),
        const SizedBox(height: 8),
        SettingsExclusiveChips<AgentScheduleInterval>(
          options: _cadenceOptions,
          value: mandate.cadencePreference,
          onChanged: mandate.setCadencePreference,
          hintFor: (interval) =>
              'About every ${interval.label.toLowerCase()}',
        ),
        const SizedBox(height: settingsSectionGap),
        SettingsSubsectionLabel(
          'Risk rails',
          key: widget.subsectionKeys?['riskRails'],
          description:
              'Hard caps for Invest interest size, Autopilot fills per day '
              '(UTC), optional daily loss stop, and max notional per order.',
        ),
        const SizedBox(height: 8),
        _riskRailsFields(mandate),
      ],
    );
  }
}
