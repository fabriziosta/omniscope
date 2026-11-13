import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/crypto/crypto_com/crypto_com_exchange_client.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

class DataSourcesSectionBody extends StatelessWidget {
  const DataSourcesSectionBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final settings = context.watch<DataSourceSettings>();
    final equityRegistry = context.watch<EquityDataSourceRegistry>();
    final cryptoRegistry = context.watch<CryptoExchangeRegistry>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSubsectionLabel(
          'Market providers',
          description:
              'Choose which sources fetch indices, ETFs, and stocks. '
              'More providers can be added later.',
        ),
        const SizedBox(height: 12),
        if (equityRegistry.all.isEmpty)
          Text('No market providers registered.', style: theme.textTheme.muted)
        else
          for (var i = 0; i < equityRegistry.all.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SettingsDataSourceToggleTile(
              title: equityRegistry.all[i].source.displayName,
              subtitle: equityRegistry.all[i].source.description.isEmpty
                  ? 'Equities market data'
                  : equityRegistry.all[i].source.description,
              enabled: settings.isMarketEnabled(
                equityRegistry.all[i].source.id,
              ),
              onChanged: (value) => settings.setMarketEnabled(
                equityRegistry.all[i].source.id,
                value,
              ),
            ),
          ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Crypto venues',
          description:
              'Choose which exchanges appear under Markets and supply live quotes. '
              'Crypto.com can use API credentials from .env or from this screen '
              '(saved both ways when possible).',
        ),
        const SizedBox(height: 12),
        if (cryptoRegistry.exchanges.isEmpty)
          Text(
            'No crypto exchanges registered.',
            style: theme.textTheme.muted,
          )
        else
          for (var i = 0; i < cryptoRegistry.exchanges.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SettingsDataSourceToggleTile(
              title: cryptoRegistry.exchanges[i].exchange.displayName,
              subtitle:
                  '${cryptoRegistry.exchanges[i].exchange.defaultSymbols.length} '
                  'default pairs',
              enabled: settings.isCryptoEnabled(
                cryptoRegistry.exchanges[i].exchange.id,
              ),
              onChanged: (value) => settings.setCryptoEnabled(
                cryptoRegistry.exchanges[i].exchange.id,
                value,
              ),
            ),
          ],
        const SizedBox(height: 20),
        const SettingsSubsectionLabel(
          'Credentials',
          description:
              'Optional. Key + secret unlock Live balances on Portfolio and '
              'live order placement for agent Confirm / Autopilot. '
              'Suggested from .env when present; saving writes back when possible.',
        ),
        const SizedBox(height: 12),
        const _CryptoComCredentialsCard(),
      ],
    );
  }
}

class _CryptoComCredentialsCard extends StatelessWidget {
  const _CryptoComCredentialsCard();

  static const _exchangeId = 'crypto_com';

  Future<void> _openEditor(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final initial = secrets.exchangeCredentialsFor(_exchangeId);
    final result = await showShadDialog<_CryptoComCredsResult>(
      context: context,
      builder: (context) => _CryptoComCredentialsDialog(
        initial: initial,
        canWriteEnvFile: secrets.canWriteEnvFile,
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.clear) {
      await secrets.clearExchangeCredentials(_exchangeId);
      if (!context.mounted) return;
      showAppToast(
        context,
        description: 'Crypto.com credentials cleared',
      );
      return;
    }

    await secrets.setExchangeCredentials(
      _exchangeId,
      ExchangeCredentials(
        apiKey: result.apiKey,
        apiSecret: result.apiSecret,
        apiToken: result.apiToken,
      ),
    );
    if (!context.mounted) return;
    showAppToast(
      context,
      description: 'Crypto.com credentials saved',
    );
  }

  @override
  Widget build(BuildContext context) {
    final secrets = context.watch<EnvSecretsRepository>();
    final creds = secrets.exchangeCredentialsFor(_exchangeId);
    final liveReady = creds.hasApiKey && creds.hasApiSecret;
    final subtitle = !creds.isConfigured && !creds.hasApiSecret
        ? 'Not configured — public market data still works'
        : liveReady
            ? 'Configured — Live portfolio + trading ready'
            : 'Partial — Live portfolio / trading need key and secret';

    return SettingsConnectionCard(
      title: CryptoComExchangeClient.meta.displayName,
      subtitle: subtitle,
      icon: LucideIcons.keyRound,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => _openEditor(context),
        child: Text(
          creds.isConfigured || creds.hasApiSecret ? 'Edit' : 'Configure',
        ),
      ),
    );
  }
}

class _CryptoComCredsResult {
  const _CryptoComCredsResult({
    required this.apiKey,
    required this.apiSecret,
    required this.apiToken,
    required this.clear,
  });

  const _CryptoComCredsResult.save({
    required this.apiKey,
    required this.apiSecret,
    required this.apiToken,
  }) : clear = false;

  const _CryptoComCredsResult.clear()
      : apiKey = '',
        apiSecret = '',
        apiToken = '',
        clear = true;

  final String apiKey;
  final String apiSecret;
  final String apiToken;
  final bool clear;
}

class _CryptoComCredentialsDialog extends StatefulWidget {
  const _CryptoComCredentialsDialog({
    required this.initial,
    required this.canWriteEnvFile,
  });

  final ExchangeCredentials initial;
  final bool canWriteEnvFile;

  @override
  State<_CryptoComCredentialsDialog> createState() =>
      _CryptoComCredentialsDialogState();
}

class _CryptoComCredentialsDialogState
    extends State<_CryptoComCredentialsDialog> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TextEditingController _apiTokenController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.initial.apiKey ?? '');
    _apiSecretController =
        TextEditingController(text: widget.initial.apiSecret ?? '');
    _apiTokenController =
        TextEditingController(text: widget.initial.apiToken ?? '');
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _CryptoComCredsResult.save(
        apiKey: _apiKeyController.text.trim(),
        apiSecret: _apiSecretController.text.trim(),
        apiToken: _apiTokenController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final suggested = widget.initial.isConfigured || widget.initial.hasApiSecret;

    return ShadDialog(
      title: const Text('Crypto.com credentials'),
      description: Text(
        'Suggested from .env when present. '
        'Key and secret unlock Live balances and agent trade suggestions. '
        '${widget.canWriteEnvFile ? 'Saving also updates the project .env file.' : 'Saving keeps keys on this device (project .env write unavailable here).'}',
      ),
      actions: [
        if (suggested)
          ShadButton.outline(
            onPressed: () =>
                Navigator.of(context).pop(const _CryptoComCredsResult.clear()),
            child: const Text('Clear'),
          ),
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('API key', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _apiKeyController,
                obscureText: true,
                placeholder: const Text('OMNISCOPE_CRYPTO_COM_API_KEY'),
              ),
              const SizedBox(height: 14),
              Text('API secret', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _apiSecretController,
                obscureText: true,
                placeholder: const Text('OMNISCOPE_CRYPTO_COM_API_SECRET'),
              ),
              const SizedBox(height: 14),
              Text('API token (optional)', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _apiTokenController,
                obscureText: true,
                placeholder: const Text('OMNISCOPE_CRYPTO_COM_API_TOKEN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
