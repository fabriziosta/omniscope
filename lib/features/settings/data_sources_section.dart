import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/venues/venue_catalog.dart';
import '../../data/venues/venue_credential_schema.dart';
import '../../data/venues/venue_trading_mode.dart';
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
    final brokerRegistry = context.watch<BrokerExchangeRegistry>();
    final venueCatalog = context.watch<VenueCatalog>();

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
              'Choose which exchanges appear under Markets and supply live '
              'quotes. Credentials below unlock Live balances and trading.',
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
          'Brokers',
          description:
              'Equity brokers for Live portfolio balances and agent Confirm / '
              'Autopilot. Quotes still come from market providers above.',
        ),
        const SizedBox(height: 12),
        if (brokerRegistry.brokers.isEmpty)
          Text(
            'No brokers registered.',
            style: theme.textTheme.muted,
          )
        else
          for (var i = 0; i < brokerRegistry.brokers.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SettingsDataSourceToggleTile(
              title: brokerRegistry.brokers[i].broker.displayName,
              subtitle: brokerRegistry.brokers[i].broker.description.isEmpty
                  ? 'Stocks and ETFs'
                  : brokerRegistry.brokers[i].broker.description,
              enabled: settings.isBrokerEnabled(
                brokerRegistry.brokers[i].broker.id,
              ),
              onChanged: (value) => settings.setBrokerEnabled(
                brokerRegistry.brokers[i].broker.id,
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
        for (var i = 0; i < venueCatalog.credentialSchemas.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _VenueCredentialsCard(schema: venueCatalog.credentialSchemas[i]),
        ],
      ],
    );
  }
}

class _VenueCredentialsCard extends StatelessWidget {
  const _VenueCredentialsCard({required this.schema});

  final VenueCredentialSchema schema;

  Future<void> _openEditor(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final initial = secrets.exchangeCredentialsFor(schema.venueId);
    final result = await showShadDialog<_VenueCredsResult>(
      context: context,
      builder: (context) => _VenueCredentialsDialog(
        schema: schema,
        initial: initial,
        canWriteEnvFile: secrets.canWriteEnvFile,
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.clear) {
      await secrets.clearExchangeCredentials(schema.venueId);
      if (!context.mounted) return;
      showAppToast(
        context,
        description: '${schema.displayName} credentials cleared',
      );
      return;
    }

    await secrets.setExchangeCredentials(
      schema.venueId,
      ExchangeCredentials(
        apiKey: result.apiKey,
        apiSecret: result.apiSecret,
        apiToken: result.apiToken,
        tradingMode: result.tradingMode,
      ),
    );
    if (!context.mounted) return;
    showAppToast(
      context,
      description: '${schema.displayName} credentials saved',
    );
  }

  @override
  Widget build(BuildContext context) {
    final secrets = context.watch<EnvSecretsRepository>();
    final creds = secrets.exchangeCredentialsFor(schema.venueId);

    return SettingsConnectionCard(
      title: schema.displayName,
      subtitle: schema.subtitleFor(creds),
      icon: LucideIcons.keyRound,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => _openEditor(context),
        child: Text(
          creds.isConfigured ||
                  creds.hasApiSecret ||
                  creds.tradingMode != null
              ? 'Edit'
              : 'Configure',
        ),
      ),
    );
  }
}

class _VenueCredsResult {
  const _VenueCredsResult({
    required this.apiKey,
    required this.apiSecret,
    required this.apiToken,
    required this.tradingMode,
    required this.clear,
  });

  const _VenueCredsResult.save({
    required this.apiKey,
    required this.apiSecret,
    required this.apiToken,
    this.tradingMode,
  }) : clear = false;

  const _VenueCredsResult.clear()
      : apiKey = '',
        apiSecret = '',
        apiToken = '',
        tradingMode = null,
        clear = true;

  final String apiKey;
  final String apiSecret;
  final String apiToken;
  final VenueTradingMode? tradingMode;
  final bool clear;
}

class _VenueCredentialsDialog extends StatefulWidget {
  const _VenueCredentialsDialog({
    required this.schema,
    required this.initial,
    required this.canWriteEnvFile,
  });

  final VenueCredentialSchema schema;
  final ExchangeCredentials initial;
  final bool canWriteEnvFile;

  @override
  State<_VenueCredentialsDialog> createState() =>
      _VenueCredentialsDialogState();
}

class _VenueCredentialsDialogState extends State<_VenueCredentialsDialog> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TextEditingController _apiTokenController;
  late VenueTradingMode _tradingMode;

  @override
  void initState() {
    super.initState();
    _apiKeyController =
        TextEditingController(text: widget.initial.apiKey ?? '');
    _apiSecretController =
        TextEditingController(text: widget.initial.apiSecret ?? '');
    _apiTokenController =
        TextEditingController(text: widget.initial.apiToken ?? '');
    _tradingMode = widget.initial.tradingMode ??
        widget.schema.defaultTradingMode;
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
      _VenueCredsResult.save(
        apiKey: _apiKeyController.text.trim(),
        apiSecret: _apiSecretController.text.trim(),
        apiToken: _apiTokenController.text.trim(),
        tradingMode:
            widget.schema.supportsTradingMode ? _tradingMode : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final schema = widget.schema;
    final suggested = widget.initial.isConfigured ||
        widget.initial.hasApiSecret ||
        widget.initial.tradingMode != null;

    return ShadDialog(
      title: Text('${schema.displayName} credentials'),
      description: Text(
        'Suggested from .env when present. '
        'Key and secret unlock Live balances and agent trade suggestions. '
        '${widget.canWriteEnvFile ? 'Saving also updates the project .env file.' : 'Saving keeps keys on this device (project .env write unavailable here).'}',
      ),
      actions: [
        if (suggested)
          ShadButton.outline(
            onPressed: () =>
                Navigator.of(context).pop(const _VenueCredsResult.clear()),
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
              if (schema.supportsTradingMode) ...[
                Text('Trading mode', style: theme.textTheme.small),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _tradingMode == VenueTradingMode.paper
                          ? ShadButton(
                              onPressed: () {},
                              child: const Text('Paper'),
                            )
                          : ShadButton.outline(
                              onPressed: () => setState(
                                () => _tradingMode = VenueTradingMode.paper,
                              ),
                              child: const Text('Paper'),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _tradingMode == VenueTradingMode.live
                          ? ShadButton(
                              onPressed: () {},
                              child: const Text('Live'),
                            )
                          : ShadButton.outline(
                              onPressed: () => setState(
                                () => _tradingMode = VenueTradingMode.live,
                              ),
                              child: const Text('Live'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Paper and live use different API keys from the broker. '
                  'Mode only selects the API host.',
                  style: theme.textTheme.muted,
                ),
                const SizedBox(height: 14),
              ],
              if (schema.requiresApiKey) ...[
                Text('API key', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _apiKeyController,
                  obscureText: true,
                  placeholder: Text(schema.apiKeyEnvName),
                ),
                const SizedBox(height: 14),
              ],
              if (schema.requiresApiSecret) ...[
                Text('API secret', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _apiSecretController,
                  obscureText: true,
                  placeholder: Text(schema.apiSecretEnvName),
                ),
                const SizedBox(height: 14),
              ],
              if (schema.requiresApiToken) ...[
                Text(
                  schema.apiTokenOptional
                      ? 'API token (optional)'
                      : 'API token',
                  style: theme.textTheme.small,
                ),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _apiTokenController,
                  obscureText: true,
                  placeholder: Text(schema.apiTokenEnvName),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
