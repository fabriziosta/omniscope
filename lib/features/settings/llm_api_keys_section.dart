import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/llm_api_key_config.dart';
import '../../data/agents/llm_connection_health.dart';
import '../../data/agents/llm_connection_status_store.dart';
import '../../data/agents/llm_model_catalog.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/models.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import 'settings_option_tiles.dart';

/// Lists every LLM provider: key + light/heavy model prefs.
class LlmApiKeysSectionBody extends StatefulWidget {
  const LlmApiKeysSectionBody({super.key});

  @override
  State<LlmApiKeysSectionBody> createState() => _LlmApiKeysSectionBodyState();
}

class _LlmApiKeysSectionBodyState extends State<LlmApiKeysSectionBody> {
  LlmModelCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    LlmModelCatalog.load().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final secrets = context.watch<EnvSecretsRepository>();
    final runtime = context.watch<LlmRuntimeSettings>();
    final statusStore = context.watch<LlmConnectionStatusStore>();
    final catalog = _catalog;
    final providers = providersOrderedByConfiguredKey(
      (p) => secrets.llmKeyFor(p) != null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSubsectionLabel(
          'LLM API keys & models',
          description:
              'Add keys for each provider you use. Pick a light model '
              '(research) and a heavy model (trading). Save or Test connection '
              'to verify the key still works — Agents share these keys.',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < providers.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ProviderKeyRow(
            provider: providers[i],
            hasKey: secrets.llmKeyFor(providers[i]) != null,
            prefs: runtime.prefsFor(providers[i]),
            catalog: catalog,
            probeResult: statusStore.resultFor(providers[i]),
            probing: statusStore.isProbing(providers[i]),
          ),
        ],
      ],
    );
  }
}

/// Configured (green) providers first; unconfigured stay at the bottom.
/// Relative enum order is preserved within each group.
@visibleForTesting
List<LlmProvider> providersOrderedByConfiguredKey(
  bool Function(LlmProvider provider) hasKey,
) {
  final configured = <LlmProvider>[];
  final unconfigured = <LlmProvider>[];
  for (final provider in LlmProvider.values) {
    if (hasKey(provider)) {
      configured.add(provider);
    } else {
      unconfigured.add(provider);
    }
  }
  return [...configured, ...unconfigured];
}

class _ProviderKeyRow extends StatelessWidget {
  const _ProviderKeyRow({
    required this.provider,
    required this.hasKey,
    required this.prefs,
    required this.catalog,
    required this.probeResult,
    required this.probing,
  });

  final LlmProvider provider;
  final bool hasKey;
  final LlmProviderRuntimePrefs? prefs;
  final LlmModelCatalog? catalog;
  final LlmConnectionResult? probeResult;
  final bool probing;

  Future<void> _openEditor(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final runtime = context.read<LlmRuntimeSettings>();
    final statusStore = context.read<LlmConnectionStatusStore>();
    final catalog = this.catalog ?? await LlmModelCatalog.load();
    if (!context.mounted) return;
    final initialKey = secrets.llmKeyFor(provider) ?? '';
    final existing = prefs ??
        LlmProviderRuntimePrefs.withCatalogDefaults(
          provider: provider,
          catalog: catalog,
        );
    final result = await showShadDialog<_KeyEditResult>(
      context: context,
      builder: (context) => _LlmApiKeyDialog(
        provider: provider,
        initialKey: initialKey,
        initialPrefs: existing,
        catalog: catalog,
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.clear) {
      await secrets.setLlmApiKey(provider, '');
      await runtime.clearProvider(provider);
      statusStore.clear(provider);
      if (!context.mounted) return;
      showAppToast(
        context,
        title: '${provider.label} cleared',
        description: 'Removed from this device.',
      );
      return;
    }

    await secrets.setLlmApiKey(provider, result.apiKey);
    await runtime.upsert(result.prefs);
    if (!context.mounted) return;
    showAppToast(
      context,
      title: '${provider.label} saved',
      description: 'Checking connection…',
    );
    await _runProbe(
      context,
      apiKey: result.apiKey,
      prefs: result.prefs,
      announce: true,
    );
  }

  Future<void> _runProbe(
    BuildContext context, {
    required String apiKey,
    required LlmProviderRuntimePrefs? prefs,
    required bool announce,
  }) async {
    final statusStore = context.read<LlmConnectionStatusStore>();
    final result = await statusStore.probeProvider(
      provider: provider,
      apiKey: apiKey,
      prefs: prefs,
    );
    if (!context.mounted || !announce) return;
    if (result.isOk) {
      showAppToast(
        context,
        title: '${provider.label} connected',
        description: 'Key works for listing models.',
      );
    } else {
      showAppToast(
        context,
        title: '${provider.label} needs attention',
        description: result.message,
        destructive: true,
      );
    }
  }

  Future<void> _testConnection(BuildContext context) async {
    final secrets = context.read<EnvSecretsRepository>();
    final key = secrets.llmKeyFor(provider);
    if (key == null || key.isEmpty) return;
    await _runProbe(
      context,
      apiKey: key,
      prefs: prefs,
      announce: true,
    );
  }

  Color _statusColor(BuildContext context) {
    if (!hasKey) return BrandColors.lossOf(context);
    if (probing) return ShadTheme.of(context).colorScheme.primary;
    final kind = probeResult?.kind;
    if (kind == LlmConnectionKind.ok) return BrandColors.gainOf(context);
    if (kind != null && kind != LlmConnectionKind.ok) {
      return BrandColors.lossOf(context);
    }
    // Saved, not checked this session.
    return BrandColors.gainOf(context);
  }

  String _statusSubtitle() {
    if (!hasKey) return 'No key yet — Agents need one to chat';
    if (probing) return 'Checking connection…';
    final probe = probeResult;
    if (probe != null) {
      return LlmConnectionHealth.statusLabel(probe.kind);
    }
    final light = prefs?.lightModelId.trim() ?? '';
    final heavy = prefs?.heavyModelId.trim() ?? '';
    final models = [
      if (light.isNotEmpty) 'Light: $light',
      if (heavy.isNotEmpty) 'Heavy: $heavy',
    ].join(' · ');
    if (models.isEmpty) return 'Saved — not checked yet';
    return '$models · Not checked yet';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final statusColor = _statusColor(context);
    final subtitle = _statusSubtitle();

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
              AppTooltip(
                message: subtitle.isEmpty ? provider.label : subtitle,
                wrapDetector: true,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.label, style: theme.textTheme.large),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (hasKey)
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed:
                          probing ? null : () => _testConnection(context),
                      child: Text(probing ? 'Testing…' : 'Test'),
                    ),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: probing ? null : () => _openEditor(context),
                    child: Text(hasKey ? 'Edit' : 'Add'),
                  ),
                ],
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
    required this.prefs,
    required this.clear,
  });

  const _KeyEditResult.save({
    required this.apiKey,
    required this.prefs,
  }) : clear = false;

  const _KeyEditResult.clear()
      : apiKey = '',
        prefs = const LlmProviderRuntimePrefs(provider: LlmProvider.gemini),
        clear = true;

  final String apiKey;
  final LlmProviderRuntimePrefs prefs;
  final bool clear;
}

class _LlmApiKeyDialog extends StatefulWidget {
  const _LlmApiKeyDialog({
    required this.provider,
    required this.initialKey,
    required this.initialPrefs,
    required this.catalog,
  });

  final LlmProvider provider;
  final String initialKey;
  final LlmProviderRuntimePrefs initialPrefs;
  final LlmModelCatalog catalog;

  @override
  State<_LlmApiKeyDialog> createState() => _LlmApiKeyDialogState();
}

class _LlmApiKeyDialogState extends State<_LlmApiKeyDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _baseUrl;
  late final TextEditingController _lightCustom;
  late final TextEditingController _heavyCustom;
  late String _lightModelId;
  late String _heavyModelId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey);
    _baseUrl = TextEditingController(text: widget.initialPrefs.baseUrl ?? '');
    _lightModelId = widget.initialPrefs.lightModelId;
    _heavyModelId = widget.initialPrefs.heavyModelId;
    _lightCustom = TextEditingController(text: _lightModelId);
    _heavyCustom = TextEditingController(text: _heavyModelId);
    if (_lightModelId.isEmpty) {
      _lightModelId = widget.catalog.suggestedModelId(
            widget.provider,
            preferredWeight: ModelWeight.light,
          ) ??
          '';
      _lightCustom.text = _lightModelId;
    }
    if (_heavyModelId.isEmpty) {
      _heavyModelId = widget.catalog.suggestedModelId(
            widget.provider,
            preferredWeight: ModelWeight.heavy,
          ) ??
          '';
      _heavyCustom.text = _heavyModelId;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _baseUrl.dispose();
    _lightCustom.dispose();
    _heavyCustom.dispose();
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
    final isCustom = widget.provider == LlmProvider.custom;
    final light = isCustom ? _lightCustom.text.trim() : _lightModelId.trim();
    final heavy = isCustom ? _heavyCustom.text.trim() : _heavyModelId.trim();
    if (light.isEmpty && heavy.isEmpty) {
      showAppToast(
        context,
        description: 'Pick at least one light or heavy model.',
        destructive: true,
      );
      return;
    }
    if (isCustom && _baseUrl.text.trim().isEmpty) {
      showAppToast(
        context,
        description: 'Base URL is required for Custom.',
        destructive: true,
      );
      return;
    }
    Navigator.of(context).pop(
      _KeyEditResult.save(
        apiKey: key,
        prefs: LlmProviderRuntimePrefs(
          provider: widget.provider,
          lightModelId: light,
          heavyModelId: heavy,
          baseUrl: isCustom ? _baseUrl.text.trim() : null,
          priority: widget.initialPrefs.priority,
          enabled: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final envName = LlmApiKeyConfig.envNameFor(widget.provider);
    final hasExisting = widget.initialKey.isNotEmpty;
    final models = widget.catalog.modelsFor(widget.provider);
    final isCustom = widget.provider == LlmProvider.custom;

    return ShadDialog(
      title: Text('${widget.provider.label} API key'),
      description: Text(
        'Keys stay on this device only in your omniscope.json config. '
        'Light models suit research; heavy models suit trading checks. '
        'Saving checks that the key can list models.',
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
            if (isCustom) ...[
              const SizedBox(height: 14),
              Text('Base URL', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _baseUrl,
                placeholder: const Text('https://…'),
              ),
              const SizedBox(height: 14),
              Text('Light model id', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(controller: _lightCustom),
              const SizedBox(height: 14),
              Text('Heavy model id', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(controller: _heavyCustom),
            ] else if (models.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Light model', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadSelect<String>(
                minWidth: double.infinity,
                initialValue: _lightModelId.isEmpty ? null : _lightModelId,
                placeholder: const Text('Select light model'),
                options: [
                  for (final m in models)
                    ShadOption(value: m.id, child: Text(m.label)),
                ],
                selectedOptionBuilder: (context, value) {
                  final label =
                      widget.catalog.labelFor(widget.provider, value) ?? value;
                  return Text(label);
                },
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _lightModelId = value);
                },
              ),
              const SizedBox(height: 14),
              Text('Heavy model', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadSelect<String>(
                minWidth: double.infinity,
                initialValue: _heavyModelId.isEmpty ? null : _heavyModelId,
                placeholder: const Text('Select heavy model'),
                options: [
                  for (final m in models)
                    ShadOption(value: m.id, child: Text(m.label)),
                ],
                selectedOptionBuilder: (context, value) {
                  final label =
                      widget.catalog.labelFor(widget.provider, value) ?? value;
                  return Text(label);
                },
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _heavyModelId = value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
