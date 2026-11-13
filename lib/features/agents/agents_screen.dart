import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/llm_api_key_config.dart';
import '../../data/agents/llm_model_catalog.dart';
import '../../data/agents/models.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/tab_page_header.dart';
import 'agent_chat_screen.dart';

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  LlmModelCatalog? _models;

  Future<LlmModelCatalog?> _ensureModels() async {
    if (_models != null) return _models;
    try {
      final models = await LlmModelCatalog.load();
      if (!mounted) return null;
      setState(() => _models = models);
      return models;
    } catch (_) {
      if (!mounted) return null;
      showAppToast(
        context,
        description: 'Could not load model list. Try again.',
        destructive: true,
      );
      return null;
    }
  }

  Future<void> _openConnect(AgentRoleDefinition role) async {
    final models = await _ensureModels();
    if (models == null || !mounted) return;

    final existing = context.read<AgentsRepository>().forRoleId(role.id);
    final apiKeys = context.read<EnvSecretsRepository>().llmKeys;
    final result = await showShadDialog<_ConnectResult>(
      context: context,
      builder: (context) => _ConnectAgentDialog(
        role: role,
        catalog: models,
        apiKeys: apiKeys,
        initial: existing,
      ),
    );
    if (result == null || !mounted) return;

    final error = await context.read<AgentsRepository>().connect(
          roleId: role.id,
          llmProvider: result.provider,
          apiKey: result.apiKey,
          modelId: result.modelId,
          baseUrl: result.baseUrl,
        );
    if (!mounted) return;
    if (error != null) {
      showAppToast(context, description: error, destructive: true);
      return;
    }
    await context.read<EnvSecretsRepository>().setLlmApiKey(
          result.provider,
          result.apiKey,
        );
    if (!mounted) return;
    showAppToast(context, description: '${role.title} connected');
  }

  Future<void> _disconnect(AgentRoleDefinition role) async {
    await context.read<AgentsRepository>().disconnect(role.id);
    if (!mounted) return;
    showAppToast(context, description: '${role.title} disconnected');
  }

  void _openChat(AgentRoleDefinition role) {
    pushFadePage(context, AgentChatScreen(role: role));
  }

  @override
  Widget build(BuildContext context) {
    final agents = context.watch<AgentsRepository>();
    final roles = agents.availableRoles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabPageHeader(
          title: 'Agents',
          subtitle:
              'Connect an AI helper, then open chat. Keys and chats stay '
              'on this device. Roles come from the agents package manifest.',
          subtitleSpacing: 6,
        ),
        Expanded(
          child: roles.isEmpty
              ? const AppEmptyView(
                  'No agent roles found. Add a role package under '
                  'agents/omniscope_agents/ and list it in manifest.json.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final role in roles) ...[
                      _AgentCard(
                        role: role,
                        connection: agents.forRoleId(role.id),
                        catalog: _models,
                        onConnect: () => _openConnect(role),
                        onDisconnect: () => _disconnect(role),
                        onOpenChat: () => _openChat(role),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.role,
    required this.connection,
    required this.catalog,
    required this.onConnect,
    required this.onDisconnect,
    required this.onOpenChat,
  });

  final AgentRoleDefinition role;
  final AgentConnection connection;
  final LlmModelCatalog? catalog;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final modelLabel = connection.connected
        ? (catalog?.labelFor(connection.llmProvider, connection.modelId) ??
            connection.modelId)
        : null;
    final suggested = role.suggestedModelId(LlmProvider.openAi);
    final suggestedLabel = suggested == null
        ? null
        : (catalog?.labelFor(LlmProvider.openAi, suggested) ?? suggested);

    return ShadCard(
      title: Row(
        children: [
          if (!connection.connected) ...[
            _AgentConfigStatusDot(configured: connection.isConfigured),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(role.title)),
        ],
      ),
      description: Text(
        '${role.workload.label}  ·  ${role.description}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            connection.connected
                ? 'Connected · ${connection.llmProvider.label}'
                    '${modelLabel != null && modelLabel.isNotEmpty ? ' · $modelLabel' : ''}'
                : 'Not connected'
                    '${suggestedLabel != null ? ' · Suggested: $suggestedLabel' : ''}',
            style: theme.textTheme.small.copyWith(
              color: connection.connected
                  ? theme.colorScheme.foreground
                  : theme.colorScheme.mutedForeground,
            ),
          ),
          if (!connection.connected && role.suggestionNote != null) ...[
            const SizedBox(height: 6),
            Text(role.suggestionNote!, style: theme.textTheme.muted),
          ],
          const SizedBox(height: 12),
          if (connection.connected) ...[
            ShadButton(
              onPressed: onOpenChat,
              child: const Text('Open chat'),
            ),
            const SizedBox(height: 8),
            ShadButton.outline(
              onPressed: onDisconnect,
              child: const Text('Disconnect'),
            ),
          ] else
            ShadButton(
              onPressed: onConnect,
              child: const Text('Connect'),
            ),
        ],
      ),
    );
  }
}

/// Green/red status for agents listed from the manifest that are not connected.
class _AgentConfigStatusDot extends StatelessWidget {
  const _AgentConfigStatusDot({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final color =
        configured ? BrandColors.gainOf(context) : BrandColors.lossOf(context);
    final message = configured
        ? 'Model and API key are assigned.'
        : "This agent isn't using a model and doesn't have an API key "
            'assigned yet.';

    return Semantics(
      label: message,
      child: ShadTooltip(
        builder: (context) => Text(message),
        child: ShadGestureDetector(
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectResult {
  const _ConnectResult({
    required this.provider,
    required this.apiKey,
    required this.modelId,
    this.baseUrl,
  });

  final LlmProvider provider;
  final String apiKey;
  final String modelId;
  final String? baseUrl;
}

class _ConnectAgentDialog extends StatefulWidget {
  const _ConnectAgentDialog({
    required this.role,
    required this.catalog,
    required this.apiKeys,
    required this.initial,
  });

  final AgentRoleDefinition role;
  final LlmModelCatalog catalog;
  final LlmApiKeyConfig apiKeys;
  final AgentConnection initial;

  @override
  State<_ConnectAgentDialog> createState() => _ConnectAgentDialogState();
}

class _ConnectAgentDialogState extends State<_ConnectAgentDialog> {
  late LlmProvider _provider;
  late String? _modelId;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _customModelController;
  late final TextEditingController _baseUrlController;

  /// Last key we auto-filled from [.env], so switching providers can replace it
  /// without wiping a key the user typed by hand.
  String? _preloadedKey;

  @override
  void initState() {
    super.initState();
    _provider = widget.initial.llmProvider;
    final initialKey = widget.initial.apiKey.isNotEmpty
        ? widget.initial.apiKey
        : (widget.apiKeys.keyFor(_provider) ?? '');
    if (widget.initial.apiKey.isEmpty && initialKey.isNotEmpty) {
      _preloadedKey = initialKey;
    }
    _apiKeyController = TextEditingController(text: initialKey);
    _customModelController = TextEditingController(
      text: widget.initial.llmProvider == LlmProvider.custom
          ? widget.initial.modelId
          : '',
    );
    _baseUrlController = TextEditingController(
      text: widget.initial.baseUrl ?? '',
    );
    _modelId = _resolveModelId(_provider, widget.initial.modelId);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  String? _resolveModelId(LlmProvider provider, String? preferred) {
    if (provider == LlmProvider.custom) return null;
    final roleSuggested = widget.role.suggestedModelId(provider);
    return widget.catalog.suggestedModelId(
      provider,
      preferredId: (preferred != null && preferred.isNotEmpty)
          ? preferred
          : roleSuggested,
      preferredWeight: widget.role.workload.preferredModelWeight,
    );
  }

  void _applyPreloadedKey(LlmProvider provider) {
    final next = widget.apiKeys.keyFor(provider) ?? '';
    final current = _apiKeyController.text;
    final canReplace =
        current.isEmpty || (_preloadedKey != null && current == _preloadedKey);
    if (canReplace) {
      _apiKeyController.text = next;
      _preloadedKey = next.isEmpty ? null : next;
    }
  }

  void _onProviderChanged(LlmProvider? value) {
    if (value == null) return;
    setState(() {
      _provider = value;
      _modelId = _resolveModelId(value, null);
      _applyPreloadedKey(value);
    });
  }

  void _submit() {
    final modelId = _provider == LlmProvider.custom
        ? _customModelController.text.trim()
        : (_modelId ?? '');
    Navigator.of(context).pop(
      _ConnectResult(
        provider: _provider,
        apiKey: _apiKeyController.text,
        modelId: modelId,
        baseUrl: _provider == LlmProvider.custom
            ? _baseUrlController.text.trim()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final models = widget.catalog.modelsFor(_provider);
    final suggestedId = widget.role.suggestedModelId(_provider);
    final suggestedLabel = suggestedId == null
        ? null
        : widget.catalog.labelFor(_provider, suggestedId);

    return ShadDialog(
      title: Text('Connect ${widget.role.title}'),
      description: Text(
        [
          ?widget.role.suggestionNote,
          if (suggestedLabel != null) 'Suggested: $suggestedLabel.',
          'Choose a model and paste your API key'
              '${widget.apiKeys.keyFor(_provider) != null ? ' (suggested from .env)' : ''}.',
          'Connecting saves the key on this device and to .env when possible.',
        ].join(' '),
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _submit,
          child: const Text('Connect'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Provider', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadSelect<LlmProvider>(
                minWidth: double.infinity,
                initialValue: _provider,
                placeholder: const Text('Select provider'),
                options: [
                  for (final p in LlmProvider.values)
                    ShadOption(value: p, child: Text(p.label)),
                ],
                selectedOptionBuilder: (context, value) => Text(value.label),
                onChanged: _onProviderChanged,
              ),
              const SizedBox(height: 14),
              if (_provider == LlmProvider.custom) ...[
                Text('Model id', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _customModelController,
                  placeholder: const Text('e.g. my-model'),
                ),
                const SizedBox(height: 14),
                Text('Base URL', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _baseUrlController,
                  placeholder: const Text('https://api.example.com/v1'),
                ),
              ] else ...[
                Text('Model', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadSelect<String>(
                  key: ValueKey('${_provider}_${widget.role.id}'),
                  minWidth: double.infinity,
                  initialValue: _modelId,
                  placeholder: const Text('Select model'),
                  options: [
                    for (final m in models)
                      ShadOption(
                        value: m.id,
                        child: Text(
                          m.id == suggestedId
                              ? '${m.label} (suggested)'
                              : m.label,
                        ),
                      ),
                  ],
                  selectedOptionBuilder: (context, value) {
                    final label = widget.catalog.labelFor(_provider, value);
                    final base = label ?? value;
                    return Text(
                      value == suggestedId ? '$base (suggested)' : base,
                    );
                  },
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _modelId = value);
                  },
                ),
              ],
              const SizedBox(height: 14),
              Text('API key', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _apiKeyController,
                obscureText: true,
                placeholder: const Text('Paste API key'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
