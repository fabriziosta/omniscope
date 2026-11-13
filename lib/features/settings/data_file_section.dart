import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/theme_settings.dart';
import '../../data/settings/user_config_reload.dart';
import '../../data/settings/user_config_store.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

class DataFileSectionBody extends StatefulWidget {
  const DataFileSectionBody({super.key});

  @override
  State<DataFileSectionBody> createState() => _DataFileSectionBodyState();
}

class _DataFileSectionBodyState extends State<DataFileSectionBody> {
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
          'live in one JSON file. Treat it like a secrets file.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel('Current location'),
        const SizedBox(height: 8),
        Text(
          locationLabel,
          style: theme.textTheme.small,
        ),
        if (config.supportsCustomPath) ...[
          const SizedBox(height: 16),
          const SettingsSubsectionLabel('Custom path (desktop)'),
          const SizedBox(height: 8),
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
        ],
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
      ],
    );
  }
}
