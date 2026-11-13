import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

class ConnectionsSectionBody extends StatelessWidget {
  const ConnectionsSectionBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final agents = context.watch<AgentsRepository>();
    final registry = context.watch<CryptoExchangeRegistry>();
    final secrets = context.watch<EnvSecretsRepository>();
    final exchangeCreds = secrets.exchangeCredentials;

    final connectedAgents = agents.availableRoles
        .where((role) => agents.forRoleId(role.id).connected)
        .map((role) => (role, agents.forRoleId(role.id)))
        .toList(growable: false);

    final connectedExchanges = registry.exchanges
        .where((client) => exchangeCreds.forId(client.exchange.id).isConfigured)
        .toList(growable: false);

    final empty = connectedAgents.isEmpty && connectedExchanges.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Agents you connected in the Agents tab, and exchanges '
          'with API credentials from .env or Settings.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 12),
        if (empty)
          Text(
            'Nothing connected yet.',
            style: theme.textTheme.muted,
          )
        else ...[
          if (connectedExchanges.isNotEmpty) ...[
            Text('Exchanges', style: theme.textTheme.small),
            const SizedBox(height: 8),
            for (var i = 0; i < connectedExchanges.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              SettingsConnectionCard(
                title: connectedExchanges[i].exchange.displayName,
                subtitle: 'API credentials configured',
                icon: LucideIcons.coins,
              ),
            ],
          ],
          if (connectedAgents.isNotEmpty) ...[
            if (connectedExchanges.isNotEmpty) const SizedBox(height: 16),
            Text('Agents', style: theme.textTheme.small),
            const SizedBox(height: 8),
            for (var i = 0; i < connectedAgents.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _AgentConnectionCard(
                role: connectedAgents[i].$1,
                connection: connectedAgents[i].$2,
              ),
            ],
          ],
        ],
      ],
    );
  }
}

class _AgentConnectionCard extends StatelessWidget {
  const _AgentConnectionCard({
    required this.role,
    required this.connection,
  });

  final AgentRoleDefinition role;
  final AgentConnection connection;

  Future<void> _disconnect(BuildContext context) async {
    await context.read<AgentsRepository>().disconnect(role.id);
    if (!context.mounted) return;
    showAppToast(
      context,
      description: '${role.title} disconnected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = connection.modelId.trim();
    final subtitle = model.isEmpty
        ? connection.llmProvider.label
        : '${connection.llmProvider.label} · $model';

    return SettingsConnectionCard(
      title: role.title,
      subtitle: subtitle,
      icon: LucideIcons.bot,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => _disconnect(context),
        child: const Text('Disconnect'),
      ),
    );
  }
}
