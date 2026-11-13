import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_toast.dart';
import 'portfolio_actions.dart';
import 'settings_option_tiles.dart';

class PrivacyDataSectionBody extends StatelessWidget {
  const PrivacyDataSectionBody({super.key});

  Future<void> _clearChats(BuildContext context) async {
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Clear all agent chats?'),
        description: const Text(
          'Deletes every saved agent conversation on this device. '
          'Agent connections and API keys are kept. This cannot be undone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear chats'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AgentChatRepository>().clearAllThreads();
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Chats cleared',
      description: 'All agent conversations were removed from this device.',
    );
  }

  Future<void> _disconnectAgents(BuildContext context) async {
    final agents = context.read<AgentsRepository>();
    final connected = agents.availableRoles
        .where((role) => agents.forRoleId(role.id).connected)
        .toList(growable: false);
    if (connected.isEmpty) {
      showAppToast(
        context,
        description: 'No agents are connected.',
      );
      return;
    }
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Disconnect all agents?'),
        description: Text(
          'Clears API keys for ${connected.length} connected '
          '${connected.length == 1 ? 'role' : 'roles'} on this device. '
          'Chat history is kept until you clear it.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    for (final role in connected) {
      await agents.disconnect(role.id);
    }
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Agents disconnected',
      description: 'API keys were cleared for connected roles.',
    );
  }

  Future<void> _clearFavorites(BuildContext context) async {
    final favorites = context.read<FavoritesRepository>();
    final marketCount = favorites.marketSymbols.length;
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Clear all favorites?'),
        description: Text(
          marketCount == 0
              ? 'Removes every starred Markets and Crypto symbol from the '
                  'data file. This cannot be undone.'
              : 'Removes $marketCount market '
                  '${marketCount == 1 ? 'favorite' : 'favorites'} and all '
                  'crypto favorites from the data file. This cannot be undone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear favorites'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await favorites.clearAll();
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Favorites cleared',
      description: 'Starred Markets and Crypto symbols were removed.',
    );
  }

  Future<void> _clearExchangeCredentials(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final registry = context.read<CryptoExchangeRegistry>();
    final configuredIds = <String>[
      for (final client in registry.exchanges)
        if (secrets.exchangeCredentialsFor(client.exchange.id).isConfigured ||
            secrets.exchangeCredentialsFor(client.exchange.id).hasApiSecret)
          client.exchange.id,
    ];
    // Also clear any known default exchange ids that may have prefs-only keys.
    for (final id in ExchangeCredentialsConfig.defaultExchangeIds) {
      if (!configuredIds.contains(id)) {
        final creds = secrets.exchangeCredentialsFor(id);
        if (creds.isConfigured || creds.hasApiSecret) {
          configuredIds.add(id);
        }
      }
    }

    if (configuredIds.isEmpty) {
      showAppToast(
        context,
        description: 'No exchange credentials are stored.',
      );
      return;
    }

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Clear exchange credentials?'),
        description: const Text(
          'Removes API key, secret, and token for configured exchanges '
          'on this device (and the project .env when writable). '
          'Public market data still works. This cannot be undone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear credentials'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Everything below stays on this device. These actions cannot be undone.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Favorites'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _clearFavorites(context),
            child: const Text('Clear all favorites'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Agent chats'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _clearChats(context),
            child: const Text('Clear all agent chats'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Agents'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: () => _disconnectAgents(context),
            child: const Text('Disconnect all agents'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Practice holdings'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.destructive(
            onPressed: () => confirmAndResetPracticePortfolio(context),
            child: const Text('Reset practice holdings'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Exchange credentials'),
        const SizedBox(height: 8),
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
