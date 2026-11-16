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
  const MandateSectionBody({super.key});

  @override
  State<MandateSectionBody> createState() => _MandateSectionBodyState();
}

class _MandateSectionBodyState extends State<MandateSectionBody> {
  late final TextEditingController _maxSymbolsController;
  late final TextEditingController _maxNotionalController;
  late final TextEditingController _maxOpenController;
  var _saving = false;

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
  }

  @override
  void dispose() {
    _maxSymbolsController.dispose();
    _maxNotionalController.dispose();
    _maxOpenController.dispose();
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

    setState(() => _saving = true);
    await mandate.setMaxSymbolCount(maxSymbols);
    await mandate.setMaxOpenProposals(maxOpen);
    await mandate.setMaxNotionalPerProposal(notional);
    if (!mounted) return;
    setState(() => _saving = false);
    _maxSymbolsController.text = mandate.maxSymbolCount.toString();
    _maxOpenController.text = mandate.maxOpenProposals.toString();
    final saved = mandate.maxNotionalPerProposal;
    _maxNotionalController.text = saved == null
        ? ''
        : (saved == saved.roundToDouble()
            ? saved.toInt().toString()
            : saved.toStringAsFixed(2));
    showAppToast(
      context,
      title: 'Risk rails saved',
      description: AppCopy.mandateRiskRailsSaved,
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
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Goal',
          description: 'What agents should optimize for.',
        ),
        const SizedBox(height: 10),
        for (final goal in MandateGoal.values) ...[
          if (goal != MandateGoal.values.first) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: goal.label,
            subtitle: goal.description,
            selected: mandate.goal == goal,
            onTap: () => mandate.setGoal(goal),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Horizon',
          description: 'How far ahead agents should think.',
        ),
        const SizedBox(height: 10),
        for (final horizon in MandateHorizon.values) ...[
          if (horizon != MandateHorizon.values.first) const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: horizon.label,
            subtitle: horizon.description,
            selected: mandate.horizon == horizon,
            onTap: () => mandate.setHorizon(horizon),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Universe',
          description: 'Which assets agents may put in Invest interest.',
        ),
        const SizedBox(height: 10),
        for (final universe in MandateUniverse.values) ...[
          if (universe != MandateUniverse.values.first)
            const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: universe.label,
            subtitle: universe.description,
            selected: mandate.universe == universe,
            onTap: () => mandate.setUniverse(universe),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Preferred cadence',
          description:
              'Suggested schedule interval when connecting agents. '
              'Does not change existing connections.',
        ),
        const SizedBox(height: 10),
        for (final interval in AgentScheduleInterval.values) ...[
          if (interval != AgentScheduleInterval.values.first)
            const SizedBox(height: 8),
          SettingsSelectableOptionTile(
            title: interval.label,
            subtitle: 'Run about every ${interval.label.toLowerCase()}',
            selected: mandate.cadencePreference == interval,
            onTap: () => mandate.setCadencePreference(interval),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Risk rails',
          description:
              'Hard caps for Invest interest size and Autopilot proposals.',
        ),
        const SizedBox(height: 10),
        Text('Max invest-interest symbols', style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadInput(
          controller: _maxSymbolsController,
          keyboardType: TextInputType.number,
          placeholder: const Text('20'),
        ),
        const SizedBox(height: 12),
        Text(
          'Max open Autopilot proposals',
          style: theme.textTheme.small,
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: _maxOpenController,
          keyboardType: TextInputType.number,
          placeholder: const Text('3'),
        ),
        const SizedBox(height: 12),
        Text(
          'Max notional per proposal (optional)',
          style: theme.textTheme.small,
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: _maxNotionalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          placeholder: const Text('Leave empty for no cap'),
        ),
        const SizedBox(height: 12),
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
}
