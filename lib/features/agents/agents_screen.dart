import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/llm_api_key_config.dart';
import '../../data/agents/llm_model_catalog.dart';
import '../../data/agents/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/tab_page_header.dart';
import 'agent_activity_pane.dart';
import 'agent_chat_screen.dart';

enum AgentsNavSection {
  roles,
  activity,
}

extension AgentsNavSectionX on AgentsNavSection {
  String get title => switch (this) {
        AgentsNavSection.roles => 'Roles',
        AgentsNavSection.activity => 'Activity',
      };

  String get subtitle => switch (this) {
        AgentsNavSection.roles => 'Connect helpers and open chat',
        AgentsNavSection.activity => 'Proposals and live order events',
      };

  IconData get icon => switch (this) {
        AgentsNavSection.roles => LucideIcons.bot,
        AgentsNavSection.activity => LucideIcons.activity,
      };
}

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  LlmModelCatalog? _models;
  ShellNavigationController? _shellNav;
  var _openingPendingConnect = false;

  AgentsNavSection _selected = AgentsNavSection.roles;
  AgentsNavSection? _narrowSelected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shellNav = context.read<ShellNavigationController>();
    if (!identical(_shellNav, shellNav)) {
      _shellNav?.removeListener(_onShellNavChanged);
      _shellNav = shellNav;
      _shellNav!.addListener(_onShellNavChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenPendingConnect();
      _maybeOpenPendingActivity();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() {
    _maybeOpenPendingConnect();
    _maybeOpenPendingActivity();
  }

  void _maybeOpenPendingActivity() {
    if (!mounted) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.agentsTabIndex) return;
    if (!shellNav.takePendingOpenAgentActivity()) return;
    final wide = MediaQuery.sizeOf(context).width >=
        MasterDetailShell.wideBreakpointDefault;
    setState(() {
      _selected = AgentsNavSection.activity;
      if (!wide) _narrowSelected = AgentsNavSection.activity;
    });
  }

  Future<void> _maybeOpenPendingConnect() async {
    if (!mounted || _openingPendingConnect) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.agentsTabIndex) return;
    final roleId = shellNav.takePendingAgentConnectRoleId();
    if (roleId == null || roleId.isEmpty) return;

    AgentRoleDefinition? role;
    for (final r in context.read<AgentsRepository>().availableRoles) {
      if (r.id == roleId) {
        role = r;
        break;
      }
    }
    if (role == null) return;

    final wide = MediaQuery.sizeOf(context).width >=
        MasterDetailShell.wideBreakpointDefault;
    setState(() {
      _selected = AgentsNavSection.roles;
      if (!wide) _narrowSelected = AgentsNavSection.roles;
    });

    _openingPendingConnect = true;
    try {
      await _openConnect(role);
    } finally {
      _openingPendingConnect = false;
    }
  }

  void _select(AgentsNavSection section, {required bool wide}) {
    setState(() {
      _selected = section;
      if (!wide) _narrowSelected = section;
    });
  }

  void _backToNavList() {
    setState(() => _narrowSelected = null);
  }

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
    final venues = context.read<TradeExecutor>().tradableVenues;
    final result = await showShadDialog<_ConnectResult>(
      context: context,
      builder: (context) => _ConnectAgentDialog(
        role: role,
        catalog: models,
        apiKeys: apiKeys,
        initial: existing,
        tradableExchangeIds: [
          for (final v in venues) (v.id, v.displayName),
        ],
      ),
    );
    if (result == null || !mounted) return;

    final error = await context.read<AgentsRepository>().connect(
          roleId: role.id,
          llmProvider: result.provider,
          apiKey: result.apiKey,
          modelId: result.modelId,
          baseUrl: result.baseUrl,
          autopilotEnabled: result.autopilotEnabled,
          autopilotExchangeId: result.autopilotExchangeId,
          autopilotMaxNotional: result.autopilotMaxNotional,
          autopilotMaxOpenProposals: result.autopilotMaxOpenProposals,
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

  Widget _rolesBody({required bool showBack}) {
    final agents = context.watch<AgentsRepository>();
    final roles = agents.availableRoles;
    context.watch<EnvSecretsRepository>();
    context.watch<DataSourceSettings>();
    final canTrade = context.read<TradeExecutor>().canTrade;

    return MasterDetailContentPane(
      title: 'Roles',
      subtitle:
          'Connect an AI helper, then open chat. Keys and chats stay on this '
          'device. Trade suggestions need a live exchange — not paper.',
      showBack: showBack,
      onBack: _backToNavList,
      backLabel: 'Agents',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canTrade)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ShadTheme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ShadTheme.of(context).colorScheme.border,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Configure an exchange under Settings → Data sources '
                        'to start getting buy/sell suggestions from trading '
                        'agents. Practice money stays manual only.',
                        style: ShadTheme.of(context).textTheme.small.copyWith(
                              color: ShadTheme.of(context)
                                  .colorScheme
                                  .secondaryForeground,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: ShadButton(
                          onPressed: () {
                            context
                                .read<ShellNavigationController>()
                                .goToSettings(sectionId: 'dataSources');
                          },
                          child: const Text('Open Data sources'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: roles.isEmpty
                ? const AppEmptyView(
                    'No agent roles found. Add a role package under '
                    'agents/omniscope_agents/ and list it in manifest.json.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InTabBackEffect(
      onBack: _narrowSelected != null ? _backToNavList : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_narrowSelected == null)
            const TabPageHeader(
              title: 'Agents',
              subtitle:
                  'Connect helpers, confirm live suggestions, and track '
                  'activity. Paper practice stays separate.',
              subtitleSpacing: 6,
            ),
          Expanded(
            child: MasterDetailShell<AgentsNavSection>(
              selected: _selected,
              narrowSelected: _narrowSelected,
              onNarrowBack: _backToNavList,
              sidebarBuilder: (context, highlighted, {required wide}) {
                return MasterDetailNavList(
                  tiles: [
                    for (final section in AgentsNavSection.values)
                      MasterDetailNavTile(
                        title: section.title,
                        icon: section.icon,
                        meta: section.subtitle,
                        selected: highlighted == section,
                        onTap: () => _select(section, wide: wide),
                      ),
                  ],
                );
              },
              contentBuilder: (context, section, {required showBack, onBack}) {
                return switch (section) {
                  AgentsNavSection.roles => KeyedSubtree(
                      key: const ValueKey('agents-roles'),
                      child: _rolesBody(showBack: showBack),
                    ),
                  AgentsNavSection.activity => AgentActivityPane(
                      key: const ValueKey('agents-activity'),
                      showBack: showBack,
                      onBack: onBack,
                    ),
                };
              },
            ),
          ),
        ],
      ),
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
                    '${connection.autopilotEnabled ? ' · Autopilot on' : ''}'
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
              onPressed: onConnect,
              child: const Text('Edit'),
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

    return AppTooltip(
      message: message,
      wrapDetector: true,
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
    );
  }
}

class _ConnectResult {
  const _ConnectResult({
    required this.provider,
    required this.apiKey,
    required this.modelId,
    this.baseUrl,
    this.autopilotEnabled = false,
    this.autopilotExchangeId,
    this.autopilotMaxNotional,
    this.autopilotMaxOpenProposals = 3,
  });

  final LlmProvider provider;
  final String apiKey;
  final String modelId;
  final String? baseUrl;
  final bool autopilotEnabled;
  final String? autopilotExchangeId;
  final double? autopilotMaxNotional;
  final int autopilotMaxOpenProposals;
}

class _ConnectAgentDialog extends StatefulWidget {
  const _ConnectAgentDialog({
    required this.role,
    required this.catalog,
    required this.apiKeys,
    required this.initial,
    required this.tradableExchangeIds,
  });

  final AgentRoleDefinition role;
  final LlmModelCatalog catalog;
  final LlmApiKeyConfig apiKeys;
  final AgentConnection initial;
  final List<(String id, String name)> tradableExchangeIds;

  @override
  State<_ConnectAgentDialog> createState() => _ConnectAgentDialogState();
}

class _ConnectAgentDialogState extends State<_ConnectAgentDialog> {
  late LlmProvider _provider;
  late String? _modelId;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _customModelController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _maxNotionalController;
  late bool _autopilotEnabled;
  String? _autopilotExchangeId;
  late int _maxOpen;

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
    _autopilotEnabled = widget.initial.autopilotEnabled;
    _autopilotExchangeId = widget.initial.autopilotExchangeId;
    _maxOpen = widget.initial.autopilotMaxOpenProposals;
    _maxNotionalController = TextEditingController(
      text: widget.initial.autopilotMaxNotional?.toString() ?? '',
    );
    if (_autopilotExchangeId != null &&
        !widget.tradableExchangeIds.any((e) => e.$1 == _autopilotExchangeId)) {
      _autopilotExchangeId = null;
    }
    if (_autopilotExchangeId == null &&
        widget.tradableExchangeIds.isNotEmpty) {
      _autopilotExchangeId = widget.tradableExchangeIds.first.$1;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    _baseUrlController.dispose();
    _maxNotionalController.dispose();
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
    final notionalRaw = _maxNotionalController.text.trim();
    final notional =
        notionalRaw.isEmpty ? null : double.tryParse(notionalRaw);
    Navigator.of(context).pop(
      _ConnectResult(
        provider: _provider,
        apiKey: _apiKeyController.text,
        modelId: modelId,
        baseUrl: _provider == LlmProvider.custom
            ? _baseUrlController.text.trim()
            : null,
        autopilotEnabled: _autopilotEnabled,
        autopilotExchangeId: _autopilotExchangeId,
        autopilotMaxNotional: notional,
        autopilotMaxOpenProposals: _maxOpen,
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
    final isTradingRole = widget.role.workload == AgentWorkload.trading;

    return ShadDialog(
      title: Text(
        widget.initial.connected
            ? 'Edit ${widget.role.title}'
            : 'Connect ${widget.role.title}',
      ),
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
          child: Text(widget.initial.connected ? 'Save' : 'Connect'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
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
              if (isTradingRole) ...[
                const SizedBox(height: 18),
                Text('Autopilot', style: theme.textTheme.small),
                const SizedBox(height: 6),
                Text(
                  'Off by default. When on, risk-approved suggestions submit '
                  'to a connected live exchange without Confirm. '
                  'Never uses paper practice money.',
                  style: theme.textTheme.muted,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Enable Autopilot',
                        style: theme.textTheme.p,
                      ),
                    ),
                    ShadSwitch(
                      value: _autopilotEnabled,
                      onChanged: (v) => setState(() => _autopilotEnabled = v),
                    ),
                  ],
                ),
                if (_autopilotEnabled) ...[
                  const SizedBox(height: 12),
                  Text('Target exchange', style: theme.textTheme.small),
                  const SizedBox(height: 6),
                  if (widget.tradableExchangeIds.isEmpty)
                    Text(
                      'No tradable exchange yet. Configure credentials under '
                      'Settings → Data sources.',
                      style: theme.textTheme.muted,
                    )
                  else
                    ShadSelect<String>(
                      minWidth: double.infinity,
                      initialValue: _autopilotExchangeId,
                      placeholder: const Text('Select exchange'),
                      options: [
                        for (final e in widget.tradableExchangeIds)
                          ShadOption(value: e.$1, child: Text(e.$2)),
                      ],
                      selectedOptionBuilder: (context, value) {
                        for (final e in widget.tradableExchangeIds) {
                          if (e.$1 == value) return Text(e.$2);
                        }
                        return Text(value);
                      },
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _autopilotExchangeId = value);
                      },
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Max open pending proposals',
                    style: theme.textTheme.small,
                  ),
                  const SizedBox(height: 6),
                  ShadSelect<int>(
                    minWidth: double.infinity,
                    initialValue: _maxOpen,
                    options: [
                      for (final n in const [1, 2, 3, 5, 10])
                        ShadOption(value: n, child: Text('$n')),
                    ],
                    selectedOptionBuilder: (context, value) => Text('$value'),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _maxOpen = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Max notional (optional)',
                    style: theme.textTheme.small,
                  ),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _maxNotionalController,
                    placeholder: const Text('e.g. 100'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
