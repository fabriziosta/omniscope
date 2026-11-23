import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/market/exchange_credentials.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/mandate_settings.dart';
import '../../data/settings/theme_settings.dart';
import '../../data/settings/user_config_reload.dart';
import '../../data/settings/user_config_store.dart';
import '../../data/venues/venue_catalog.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import 'portfolio_actions.dart';
import 'settings_option_tiles.dart';

/// Config file location, backup, and clear-local-data actions.
class DataPrivacySectionBody extends StatefulWidget {
  const DataPrivacySectionBody({super.key, this.subsectionKeys});

  /// Optional scroll anchors keyed by subsection id.
  final Map<String, GlobalKey>? subsectionKeys;

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
      llmRuntime: context.read<LlmRuntimeSettings>(),
      agentApp: context.read<AgentAppSettings>(),
      mandate: context.read<MandateSettings>(),
      agentMemory: context.read<AgentMemoryRepository>(),
      investInterestProposals:
          context.read<InvestInterestProposalRepository>(),
      tradeProposals: context.read<TradeProposalRepository>(),
      venues: context.read<VenueCatalog>(),
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
    final ok = await showAppDialog<bool>(
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
            autofocus: true,
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
    final hadSchedule =
        context.read<AgentAppSettings>().scheduleEnabled ||
            context.read<AgentAppSettings>().scheduleChatId != null;
    await context.read<AgentChatRepository>().clearAllThreads();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Chats cleared',
      description: hadSchedule
          ? 'All agent conversations were removed. Schedule was stopped.'
          : 'All agent conversations were removed from this device.',
    );
  }

  Future<void> _resetLlmAndAgentPrefs() async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Reset LLM and agent prefs?',
      description:
          'Clears all LLM API keys, light/heavy model picks, Autopilot, '
          'Schedule, and role overrides on this device. Chat history is kept '
          'until you clear it. This cannot be undone.',
      confirmLabel: 'Reset',
    );
    if (!ok || !mounted) return;
    final secrets = context.read<EnvSecretsRepository>();
    final llmRuntime = context.read<LlmRuntimeSettings>();
    final agentApp = context.read<AgentAppSettings>();
    final agents = context.read<AgentsRepository>();
    await secrets.clearAllLlmApiKeys();
    await llmRuntime.clearAll();
    await agentApp.resetToDefaults();
    await agents.clearAllConnections();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'LLM and agent prefs reset',
      description:
          'Provider keys and agent settings were cleared on this device.',
    );
  }

  Future<void> _clearTradeActivity() async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear proposals and activity?',
      description:
          'Removes saved agent trade and Invest interest proposals, the '
          'Activity tab timeline, and shell notifications on this device. '
          'Chat history is kept. This cannot be undone.',
      confirmLabel: 'Clear activity',
    );
    if (!ok || !mounted) return;
    final proposals = context.read<TradeProposalRepository>();
    final investInterest =
        context.read<InvestInterestProposalRepository>();
    final activity = context.read<AgentActivityRepository>();
    final notifications = context.read<AppNotificationRepository>();
    await proposals.clearAll();
    await investInterest.clearAll();
    await activity.clearAll();
    await notifications.clearAll();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Activity cleared',
      description:
          'Proposals, agent activity, and notifications were removed.',
    );
  }

  Future<void> _clearFavorites() async {
    final favorites = context.read<FavoritesRepository>();
    final count = favorites.symbols.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear all favorites?',
      description: count == 0
          ? 'Removes every starred Markets symbol from the data file. '
              'This cannot be undone.'
          : 'Removes $count '
              '${count == 1 ? 'favorite' : 'favorites'} from the data file. '
              'This cannot be undone.',
      confirmLabel: 'Clear favorites',
    );
    if (!ok || !mounted) return;
    await favorites.clearAll();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Favorites cleared',
      description: 'Starred Markets symbols were removed.',
    );
  }

  Future<void> _clearInvestInterest() async {
    final favorites = context.read<FavoritesRepository>();
    final count = favorites.investInterestSymbols.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear invest interest?',
      description: count == 0
          ? 'Removes every Invest interest symbol from the data file. '
              'This cannot be undone.'
          : 'Removes $count invest-interest '
              '${count == 1 ? 'symbol' : 'symbols'} from the data file. '
              'This cannot be undone.',
      confirmLabel: 'Clear invest interest',
    );
    if (!ok || !mounted) return;
    await favorites.clearInvestInterest();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Invest interest cleared',
      description: 'Agent-facing invest-interest symbols were removed.',
    );
  }

  Future<void> _clearSharedMemory() async {
    final memory = context.read<AgentMemoryRepository>();
    final count = memory.facts.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear shared memory?',
      description: count == 0
          ? 'Removes every shared agent-memory fact from the data file. '
              'Chat history is kept. This cannot be undone.'
          : 'Removes $count shared memory '
              '${count == 1 ? 'fact' : 'facts'} from the data file. '
              'Chat history is kept. This cannot be undone.',
      confirmLabel: 'Clear memory',
    );
    if (!ok || !mounted) return;
    await memory.clearAll();
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Shared memory cleared',
      description: 'Agent memory facts were removed from this device.',
    );
  }

  Future<void> _clearExchangeCredentials() async {
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
        SettingsSubsectionLabel(
          'Data file location',
          key: widget.subsectionKeys?['dataFile'],
        ),
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
        SettingsSubsectionLabel(
          'Backup',
          key: widget.subsectionKeys?['backup'],
        ),
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
        SettingsSubsectionLabel(
          'Favorites',
          key: widget.subsectionKeys?['favorites'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearFavorites,
            child: const Text('Clear all favorites'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Invest interest',
          key: widget.subsectionKeys?['investInterest'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearInvestInterest,
            child: const Text('Clear invest interest'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Shared memory',
          key: widget.subsectionKeys?['sharedMemory'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearSharedMemory,
            child: const Text('Clear shared memory'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Agent chats',
          key: widget.subsectionKeys?['agentChats'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearChats,
            child: const Text('Clear all agent chats'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Trade activity',
          key: widget.subsectionKeys?['tradeActivity'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _clearTradeActivity,
            child: const Text('Clear proposals and activity'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'LLM & agents',
          key: widget.subsectionKeys?['llmAgents'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _resetLlmAndAgentPrefs,
            child: const Text('Reset LLM and agent prefs'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Practice holdings',
          key: widget.subsectionKeys?['practiceHoldings'],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.destructive(
            onPressed: () => confirmAndResetPracticePortfolio(context),
            child: const Text('Reset practice holdings'),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSubsectionLabel(
          'Exchange credentials',
          key: widget.subsectionKeys?['exchangeCredentials'],
        ),
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
