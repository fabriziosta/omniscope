import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/broker_exchange_registry.dart';
import 'llm_api_keys_section.dart';
import 'settings_option_tiles.dart';

/// LLM API keys/models plus exchange credential summary.
class ConnectionsSectionBody extends StatelessWidget {
  const ConnectionsSectionBody({super.key});

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
          'device only (and in the project .env when writable). Nothing is '
          'sent to an Omniscope server.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const LlmApiKeysSectionBody(),
        if (!hasLlm) ...[
          const SizedBox(height: 12),
          Text(
            'Add at least one provider key above to use Agents.',
            style: theme.textTheme.muted,
          ),
        ],
        if (exchangeNames.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SettingsSubsectionLabel(
            'Exchange credentials',
            description: 'Configured under Data sources.',
          ),
          const SizedBox(height: 8),
          for (final name in exchangeNames) ...[
            Text(name, style: theme.textTheme.large),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }
}
