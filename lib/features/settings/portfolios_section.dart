import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import 'portfolio_actions.dart';
import 'settings_option_tiles.dart';

class PortfoliosSectionBody extends StatefulWidget {
  const PortfoliosSectionBody({
    super.key,
    this.onOpenDataSources,
  });

  /// Optional jump to Settings → Data sources (credentials live there).
  final VoidCallback? onOpenDataSources;

  @override
  State<PortfoliosSectionBody> createState() => _PortfoliosSectionBodyState();
}

class _PortfoliosSectionBodyState extends State<PortfoliosSectionBody> {
  late final TextEditingController _cashController;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final starting = context.read<PortfolioRepository>().startingCash;
    _cashController = TextEditingController(
      text: starting == starting.roundToDouble()
          ? starting.toInt().toString()
          : starting.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _saveStartingCash() async {
    final raw = _cashController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      showAppToast(
        context,
        description: 'Enter a positive dollar amount.',
        destructive: true,
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<PortfolioRepository>().setStartingCash(amount);
    if (!mounted) return;
    setState(() => _saving = false);
    showAppToast(
      context,
      title: 'Starting cash saved',
      description:
          'Resets will use ${formatMoney(amount)}. '
          'Current practice holdings are unchanged.',
    );
  }

  String _liveStatusSubtitle({
    required bool ready,
    required bool hasPartialCreds,
  }) {
    if (ready) {
      return 'Ready — live balances show on the Portfolio tab';
    }
    if (hasPartialCreds) {
      return 'Needs key and secret — configure in Data sources';
    }
    return 'Configure credentials in Data sources to unlock Live';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final portfolio = context.watch<PortfolioRepository>();
    final dataSources = context.watch<DataSourceSettings>();
    final registry = context.watch<CryptoExchangeRegistry>();
    final secrets = context.watch<EnvSecretsRepository>();

    final descriptors = PortfolioCatalog.list(
      registry: registry,
      dataSources: dataSources,
      includePendingLive: true,
    );
    final liveDescriptors =
        descriptors.where((d) => d.isLive).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsConnectionCard(
          title: 'Practice',
          subtitle: 'Paper money for learning — stored only on this device.',
          icon: LucideIcons.wallet,
          trailing: const AppTooltip(
            message: 'Paper — practice money only',
            wrapDetector: true,
            child: ShadBadge.secondary(
              child: Text('Paper'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel(
          'Starting cash',
          description:
              'Used the next time you reset practice holdings. '
              'Saving here does not change your current cash or holdings.',
        ),
        const SizedBox(height: 10),
        Text('Amount (USD)', style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadInput(
          controller: _cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          placeholder: Text(formatMoney(portfolio.startingCash)),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton(
            onPressed: _saving ? null : _saveStartingCash,
            child: Text(_saving ? 'Saving…' : 'Save starting cash'),
          ),
        ),
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Reset practice holdings',
          description:
              'Restores starting cash and clears practice holdings. '
              'Live exchange balances are not affected.',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.destructive(
            onPressed: () => confirmAndResetPracticePortfolio(context),
            child: const Text('Reset practice holdings'),
          ),
        ),
        const SizedBox(height: 28),
        const SettingsSubsectionLabel(
          'Live portfolios',
          description:
              'Read-only balances from connected exchanges. '
              'Credentials are managed under Data sources.',
        ),
        const SizedBox(height: 12),
        if (liveDescriptors.isEmpty)
          Text(
            'No live portfolios yet. Enable a crypto exchange and add its '
            'API key and secret in Data sources to see real holdings here '
            'and on the Portfolio tab.',
            style: theme.textTheme.muted,
          )
        else
          for (var i = 0; i < liveDescriptors.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final desc = liveDescriptors[i];
                final client = registry.clientForId(desc.id);
                final ready = client?.canFetchPortfolio ?? false;
                final creds = secrets.exchangeCredentialsFor(desc.id);
                final partial = !ready &&
                    (creds.hasApiKey ||
                        creds.hasApiSecret ||
                        creds.hasApiToken);
                return SettingsConnectionCard(
                  title: desc.displayName,
                  subtitle: _liveStatusSubtitle(
                    ready: ready,
                    hasPartialCreds: partial,
                  ),
                  icon: LucideIcons.landmark,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppTooltip(
                        message: 'Live — read-only exchange balances',
                        wrapDetector: true,
                        child: ShadBadge(
                          child: Text('Live'),
                        ),
                      ),
                      if (!ready && widget.onOpenDataSources != null) ...[
                        const SizedBox(width: 8),
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          onPressed: widget.onOpenDataSources,
                          child: const Text('Data sources'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
      ],
    );
  }
}
