import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/venues/venue_catalog.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import 'llm_api_keys_section.dart';
import 'settings_option_tiles.dart';

/// LLM API keys/models plus exchange credential summary (Settings → Agents).
class ConnectionsSectionBody extends StatelessWidget {
  const ConnectionsSectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by subsection id.
  final Map<String, GlobalKey>? subsectionKeys;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final registry = context.watch<CryptoExchangeRegistry>();
    final brokers = context.watch<BrokerExchangeRegistry>();
    final secrets = context.watch<EnvSecretsRepository>();
    final runtime = context.watch<LlmRuntimeSettings>();

    final hasLlm = LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    );

    final exchangeNames = <String>[
      for (final client in registry.exchanges)
        if (secrets.exchangeCredentialsFor(client.exchange.id).isConfigured)
          client.exchange.displayName,
      for (final client in brokers.brokers)
        if (secrets.exchangeCredentialsFor(client.broker.id).isConfigured)
          client.broker.displayName,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LLM keys, models, and exchange credentials stay on this '
          'device only (in your omniscope.json config). Nothing is '
          'sent to an Omniscope server. Saving or Test checks that a '
          'provider key still works (list models) — keys are never '
          'removed automatically.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        LlmApiKeysSectionBody(
          sectionKey: subsectionKeys?['llmKeys'],
        ),
        if (!hasLlm) ...[
          const SizedBox(height: 12),
          Text(
            'Add at least one provider key above to use Agents.',
            style: theme.textTheme.muted,
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _resetLlmKeysAndModels(context),
            child: const Text('Reset LLM keys & models'),
          ),
        ),
        const SizedBox(height: 20),
        SettingsSubsectionLabel(
          'Exchange credentials',
          key: subsectionKeys?['exchangeCredentials'],
          description: 'Configured under Data sources.',
        ),
        const SizedBox(height: 8),
        if (exchangeNames.isEmpty)
          Text(
            'No exchange credentials configured yet.',
            style: theme.textTheme.muted,
          )
        else
          for (final name in exchangeNames) ...[
            Text(name, style: theme.textTheme.large),
            const SizedBox(height: 4),
          ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.destructive(
            onPressed: () => _clearExchangeCredentials(context),
            child: const Text('Clear exchange credentials'),
          ),
        ),
      ],
    );
  }
}

Future<void> _resetLlmKeysAndModels(BuildContext context) async {
  final ok = await confirmDestructiveAction(
    context,
    title: 'Reset LLM keys & models?',
    description:
        'Clears all LLM API keys and light/heavy model picks on this '
        'device. Schedule, shared memory, and chat history are kept. '
        'This cannot be undone.',
    confirmLabel: 'Reset',
  );
  if (!ok || !context.mounted) return;
  final secrets = context.read<EnvSecretsRepository>();
  final llmRuntime = context.read<LlmRuntimeSettings>();
  await secrets.clearAllLlmApiKeys();
  await llmRuntime.clearAll();
  if (!context.mounted) return;
  showAppToast(
    context,
    title: 'LLM prefs reset',
    description: 'Provider keys and model picks were cleared on this device.',
  );
}

Future<void> _clearExchangeCredentials(BuildContext context) async {
  final secrets = context.read<EnvSecretsRepository>();
  final venues = context.read<VenueCatalog>();
  final configuredIds = <String>[
    for (final id in {
      ...venues.credentialVenueIds,
      ...ExchangeCredentialsConfig.defaultExchangeIds,
    })
      if (secrets.exchangeCredentialsFor(id).isConfigured ||
          secrets.exchangeCredentialsFor(id).hasApiSecret ||
          secrets.exchangeCredentialsFor(id).tradingMode != null)
        id,
  ];

  if (configuredIds.isEmpty) {
    showAppToast(
      context,
      description: 'No exchange credentials are stored.',
    );
    return;
  }

  final ok = await confirmDestructiveAction(
    context,
    title: 'Clear exchange credentials?',
    description:
        'Removes API key, secret, and token for configured exchanges '
        'on this device. '
        'Public market data still works. This cannot be undone.',
    confirmLabel: 'Clear credentials',
  );
  if (!ok || !context.mounted) return;
  for (final id in configuredIds) {
    await secrets.clearExchangeCredentials(id);
  }
  if (!context.mounted) return;
  showAppToast(
    context,
    title: 'Credentials cleared',
    description: 'Exchange API credentials were removed from this device.',
  );
}
