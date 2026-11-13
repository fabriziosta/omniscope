import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/llm_api_key_config.dart';
import '../../data/agents/models.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';
import 'settings_option_tiles.dart';

/// Lists every LLM provider and whether a local API key is stored.
class LlmApiKeysSectionBody extends StatelessWidget {
  const LlmApiKeysSectionBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final secrets = context.watch<EnvSecretsRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'API keys are never sent to an Omniscope server. They stay on this '
          'device only (and in the project .env when writable). Uninstalling '
          'the app removes them.',
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 16),
        const SettingsSubsectionLabel(
          'Providers',
          description:
              'Add a key for each provider you want Agents to use. '
              'A red mark means no key yet; green means a key is saved locally.',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < LlmProvider.values.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ProviderKeyRow(
            provider: LlmProvider.values[i],
            hasKey: secrets.llmKeyFor(LlmProvider.values[i]) != null,
          ),
        ],
      ],
    );
  }
}

class _ProviderKeyRow extends StatelessWidget {
  const _ProviderKeyRow({
    required this.provider,
    required this.hasKey,
  });

  final LlmProvider provider;
  final bool hasKey;

  Future<void> _openEditor(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final initial = secrets.llmKeyFor(provider) ?? '';
    final result = await showShadDialog<_KeyEditResult>(
      context: context,
      builder: (context) => _LlmApiKeyDialog(
        provider: provider,
        initialKey: initial,
        canWriteEnvFile: secrets.canWriteEnvFile,
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.clear) {
      await secrets.setLlmApiKey(provider, '');
      if (!context.mounted) return;
      showAppToast(
        context,
        title: '${provider.label} key cleared',
        description: 'Removed from this device.',
      );
      return;
    }

    await secrets.setLlmApiKey(provider, result.apiKey);
    if (!context.mounted) return;
    showAppToast(
      context,
      title: '${provider.label} key saved',
      description: 'Stored only on this device.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final statusColor =
        hasKey ? BrandColors.gainOf(context) : BrandColors.lossOf(context);
    final subtitle = hasKey
        ? 'Key saved locally'
        : 'No key yet — Agents need one to connect';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: theme.radius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.label, style: theme.textTheme.large),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => _openEditor(context),
                child: Text(hasKey ? 'Edit' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyEditResult {
  const _KeyEditResult({
    required this.apiKey,
    required this.clear,
  });

  const _KeyEditResult.save(this.apiKey) : clear = false;

  const _KeyEditResult.clear()
      : apiKey = '',
        clear = true;

  final String apiKey;
  final bool clear;
}

class _LlmApiKeyDialog extends StatefulWidget {
  const _LlmApiKeyDialog({
    required this.provider,
    required this.initialKey,
    required this.canWriteEnvFile,
  });

  final LlmProvider provider;
  final String initialKey;
  final bool canWriteEnvFile;

  @override
  State<_LlmApiKeyDialog> createState() => _LlmApiKeyDialogState();
}

class _LlmApiKeyDialogState extends State<_LlmApiKeyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      showAppToast(
        context,
        description: 'Enter an API key, or use Clear.',
        destructive: true,
      );
      return;
    }
    Navigator.of(context).pop(_KeyEditResult.save(key));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final envName = LlmApiKeyConfig.envNameFor(widget.provider);
    final hasExisting = widget.initialKey.isNotEmpty;

    return ShadDialog(
      title: Text('${widget.provider.label} API key'),
      description: Text(
        'Keys stay on this device only — never uploaded to Omniscope. '
        '${widget.canWriteEnvFile ? 'Saving also updates the project .env file.' : 'Project .env write is unavailable here; the key stays in local storage.'} '
        'Uninstalling the app deletes local keys.',
      ),
      actions: [
        if (hasExisting)
          ShadButton.outline(
            onPressed: () =>
                Navigator.of(context).pop(const _KeyEditResult.clear()),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('API key', style: theme.textTheme.small),
            const SizedBox(height: 6),
            ShadInput(
              controller: _controller,
              obscureText: true,
              placeholder: Text(envName),
            ),
          ],
        ),
      ),
    );
  }
}
