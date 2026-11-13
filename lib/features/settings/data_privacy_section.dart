import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/theme_settings.dart';
import '../../data/settings/user_config_reload.dart';
import '../../data/settings/user_config_store.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import 'portfolio_actions.dart';
import 'settings_option_tiles.dart';

/// Config file location, backup, and clear-local-data actions.
class DataPrivacySectionBody extends StatefulWidget {
  const DataPrivacySectionBody({super.key});

  @override
  State<DataPrivacySectionBody> createState() => _DataPrivacySectionBodyState();
}

class _DataPrivacySectionBodyState extends State<DataPrivacySectionBody> {
  late final TextEditingController _pathController;
  bool _savingPath = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<UserConfigStore>();
    _pathController = TextEditingController(
      text: config.pathOverride ?? config.effectivePath ?? '',
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _reloadConsumers() async {
    await reloadUserConfigConsumers(
      config: context.read<UserConfigStore>(),
      theme: context.read<ThemeSettings>(),
      display: context.read<DisplaySettings>(),
      dataSources: context.read<DataSourceSettings>(),
      secrets: context.read<EnvSecretsRepository>(),
      favorites: context.read<FavoritesRepository>(),
      portfolio: context.read<PortfolioRepository>(),
      agents: context.read<AgentsRepository>(),
      chats: context.read<AgentChatRepository>(),
      cryptoRegistry: context.read<CryptoExchangeRegistry>(),
    );
  }

  Future<void> _savePath() async {
    final config = context.read<UserConfigStore>();
    setState(() => _savingPath = true);
    try {
      await config.setCustomPath(_pathController.text);
      await _reloadConsumers();
      if (!mounted) return;
      _pathController.text =
          config.pathOverride ?? config.effectivePath ?? '';
      showAppToast(
        context,
        title: 'Data file updated',
        description: config.effectivePath ?? 'Using the default location.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Could not change data file',
        description: e.toString(),
        destructive: true,
      );
    } finally {
      if (mounted) setState(() => _savingPath = false);
    }
  }

  Future<void> _useDefaultPath() async {
    final config = context.read<UserConfigStore>();
    setState(() => _savingPath = true);
    try {
      await config.setCustomPath(null);
      await _reloadConsumers();
      if (!mounted) return;
      _pathController.text = config.effectivePath ?? '';
      showAppToast(
        context,
        title: 'Using default location',
        description: config.effectivePath ?? 'Default data file restored.',
      );
    } finally {
      if (mounted) setState(() => _savingPath = false);
    }
  }

  Future<void> _export() async {
    final json = context.read<UserConfigStore>().exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Copied to clipboard',
      description:
          'Config JSON (includes API keys). Paste it somewhere safe.',
    );
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Import data file'),
        description: const Text(
          'Paste an Omniscope config JSON. This replaces favorites, '
          'settings, portfolio, chats, and API keys on this device.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ShadInput(
            controller: controller,
            placeholder: const Text('Paste JSON…'),
            maxLines: 8,
          ),
        ),
      ),
    );
    final raw = controller.text;
    controller.dispose();
    if (ok != true || !mounted) return;

    try {
      await context.read<UserConfigStore>().importJson(raw);
      await _reloadConsumers();
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Import complete',
        description: 'Local settings were replaced from the pasted JSON.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Import failed',
        description: e.toString(),
        destructive: true,
      );
    }
  }

  Future<void> _clearChats() async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear all agent chats?',
      description:
          'Deletes every saved agent conversation on this device. '
          'Agent connections and API keys are kept. This cannot be undone.',
      confirmLabel: 'Clear chats',
    );
    if (!ok || !mounted) return;
    await context.read<AgentChatRepository>().clearAllThreads();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Chats cleared',
      description: 'All agent conversations were removed from this device.',
    );
  }

  Future<void> _disconnectAgents() async {
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
    final ok = await confirmDestructiveAction(
      context,
      title: 'Disconnect all agents?',
      description:
          'Clears API keys for ${connected.length} connected '
          '${connected.length == 1 ? 'role' : 'roles'} on this device. '
          'Chat history is kept until you clear it.',
      confirmLabel: 'Disconnect',
    );
    if (!ok || !mounted) return;
    for (final role in connected) {
      await agents.disconnect(role.id);
    }
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Agents disconnected',
      description: 'API keys were cleared for connected roles.',
    );
  }

  Future<void> _clearTradeActivity() async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear trade proposals and activity?',
      description:
          'Removes saved agent trade proposals, the Activity timeline, and '
          'shell notifications on this device. Chat history is kept. '
          'This cannot be undone.',
      confirmLabel: 'Clear activity',
    );
    if (!ok || !mounted) return;
    final proposals = context.read<TradeProposalRepository>();
    final activity = context.read<AgentActivityRepository>();
    final notifications = context.read<AppNotificationRepository>();
    await proposals.clearAll();
    await activity.clearAll();
    await notifications.clearAll();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Activity cleared',
      description:
          'Trade proposals, agent activity, and notifications were removed.',
    );
  }

  Future<void> _clearFavorites() async {
    final favorites = context.read<FavoritesRepository>();
    final marketCount = favorites.marketSymbols.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear all favorites?',
      description: marketCount == 0
          ? 'Removes every starred Markets and Crypto symbol from the '
              'data file. This cannot be undone.'
          : 'Removes $marketCount market '
              '${marketCount == 1 ? 'favorite' : 'favorites'} and all '
              'crypto favorites from the data file. This cannot be undone.',
      confirmLabel: 'Clear favorites',
    );
    if (!ok || !mounted) return;
    await favorites.clearAll();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Favorites cleared',
      description: 'Starred Markets and Crypto symbols were removed.',
    );
  }

  Future<void> _clearExchangeCredentials() async {
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

    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear exchange credentials?',
      description:
          'Removes API key, secret, and token for configured exchanges '
          'on this device (and the project .env when writable). '
          'Public market data still works. This cannot be undone.',
      confirmLabel: 'Clear credentials',
    );
    if (!ok || !mounted) return;
    for (final id in configuredIds) {
      await secrets.clearExchangeCredentials(id);
    }
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Credentials cleared',
      description: 'Exchange API credentials were removed from this device.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final config = context.watch<UserConfigStore>();
    final locationLabel = config.usesFilesystem
        ? (config.effectivePath ?? 'Unknown path')
        : 'Browser storage (this device)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Credentials, favorites, appearance, portfolio, agents, and chats '
          'live in one JSON file on this device. Treat it like a secrets file.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Data file location'),
        const SizedBox(height: 8),
        if (config.supportsCustomPath) ...[
          ShadInput(
            controller: _pathController,
            placeholder: const Text('/path/to/omniscope.json'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton(
                enabled: !_savingPath,
                onPressed: _savePath,
                child: const Text('Save path'),
              ),
              ShadButton.outline(
                enabled: !_savingPath,
                onPressed: _useDefaultPath,
                child: const Text('Use default'),
              ),
            ],
          ),
          if (config.defaultPath != null) ...[
            const SizedBox(height: 8),
            Text(
              'Default: ${config.defaultPath}',
              style: theme.textTheme.muted,
            ),
          ],
        ] else
          Text(
            locationLabel,
            style: theme.textTheme.small,
          ),

        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Backup'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ShadButton.outline(
              onPressed: _export,
              child: const Text('Export (copy JSON)'),
            ),
            ShadButton.outline(
              onPressed: _import,
              child: const Text('Import…'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Clear or reset data below. These actions cannot be undone.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Favorites'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearFavorites,
            child: const Text('Clear all favorites'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Agent chats'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearChats,
            child: const Text('Clear all agent chats'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Trade activity'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearTradeActivity,
            child: const Text('Clear proposals and activity'),
          ),
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Agents'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _disconnectAgents,
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
            onPressed: _clearExchangeCredentials,
            child: const Text('Clear exchange credentials'),
          ),
        ),
      ],
    );
  }
}
