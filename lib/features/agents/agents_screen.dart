import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_robustness.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/llm_api_key_config.dart';
import '../../data/agents/llm_model_catalog.dart';
import '../../data/agents/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/settings_listen_keys.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/tab_page_header.dart';
import 'agent_chat_screen.dart';
import 'agent_launch_actions.dart';

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  LlmModelCatalog? _models;
  ShellNavigationController? _shellNav;
  var _openingPendingConnect = false;
  var _openingPendingChat = false;

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
      _maybeOpenPendingChat();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() {
    _maybeOpenPendingConnect();
    _maybeOpenPendingChat();
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

    _openingPendingConnect = true;
    try {
      await _openConnect(role);
    } finally {
      _openingPendingConnect = false;
    }
  }

  Future<void> _maybeOpenPendingChat() async {
    if (!mounted || _openingPendingChat) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.agentsTabIndex) return;
    final pending = shellNav.takePendingAgentChatOpen();
    if (pending == null) return;

    AgentRoleDefinition? role;
    for (final r in context.read<AgentsRepository>().availableRoles) {
      if (r.id == pending.roleId) {
        role = r;
        break;
      }
    }
    if (role == null) {
      showAppToast(
        context,
        description: 'That agent is no longer available.',
        destructive: true,
      );
      return;
    }

    _openingPendingChat = true;
    try {
      await AgentLaunchActions.openAgentChat(
        context,
        role: role,
        initialSymbol: pending.symbol,
        autoRun: false,
      );
    } finally {
      _openingPendingChat = false;
    }
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
          scheduleEnabled: result.scheduleEnabled,
          scheduleInterval: result.scheduleInterval,
          scheduleSymbols: result.scheduleSymbols,
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
    context.select<EnvSecretsRepository, String>(exchangeCredsFingerprint);
    context.select<DataSourceSettings, String>(dataSourceFingerprint);
    final canTrade = context.read<TradeExecutor>().canTrade;
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabPageHeader(
          title: 'Agents',
          subtitle:
              'Connect helpers and open chat. Confirm suggestions on the '
              'Activity tab into Practice or live portfolios.',
          subtitleSpacing: 6,
        ),
        if (canTrade &&
            context.read<TradeExecutor>().liveVenues.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.border),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'No live exchange connected yet — trading agents '
                      'default to Practice (paper). Add credentials under '
                      'Settings → Data sources for live Confirm / Autopilot.',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.secondaryForeground,
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
                  'lib/data/agents/genkit/ and list it in assets/agents/manifest.json.',
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

    final robustness = AgentRobustness.score(role);

    return ShadCard(
      title: Row(
        children: [
          if (!connection.connected) ...[
            _AgentConfigStatusDot(configured: connection.isConfigured),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(role.title)),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: AppTooltip(
                message: AgentRobustness.tooltipMessage,
                wrapDetector: true,
                child: ShadBadge.secondary(
                  child: Text('Robustness $robustness'),
                ),
              ),
            ),
          ),
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
                    '${connection.scheduleEnabled ? ' · Schedule · ${connection.scheduleInterval.shortLabel}' : ''}'
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
    this.scheduleEnabled = false,
    this.scheduleInterval = AgentScheduleInterval.hour1,
    this.scheduleSymbols = const [],
  });

  final LlmProvider provider;
  final String apiKey;
  final String modelId;
  final String? baseUrl;
  final bool autopilotEnabled;
  final String? autopilotExchangeId;
  final double? autopilotMaxNotional;
  final int autopilotMaxOpenProposals;
  final bool scheduleEnabled;
  final AgentScheduleInterval scheduleInterval;
  final List<String> scheduleSymbols;
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
  late final TextEditingController _scheduleSymbolsController;
  late bool _autopilotEnabled;
  String? _autopilotExchangeId;
  late int _maxOpen;
  late bool _scheduleEnabled;
  late AgentScheduleInterval _scheduleInterval;

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
    _scheduleEnabled = widget.initial.scheduleEnabled;
    _scheduleInterval = widget.initial.scheduleInterval;
    _scheduleSymbolsController = TextEditingController(
      text: widget.initial.scheduleSymbols.join(', '),
    );
    if (_autopilotExchangeId != null &&
        !widget.tradableExchangeIds.any((e) => e.$1 == _autopilotExchangeId)) {
      _autopilotExchangeId = null;
    }
    // Only auto-pick when a single target exists (Practice alone).
    if (_autopilotExchangeId == null &&
        widget.tradableExchangeIds.length == 1) {
      _autopilotExchangeId = widget.tradableExchangeIds.first.$1;
    }
  }

  static const _nonePortfolio = '__none__';

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    _baseUrlController.dispose();
    _maxNotionalController.dispose();
    _scheduleSymbolsController.dispose();
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
    if (_autopilotEnabled &&
        (_autopilotExchangeId == null || _autopilotExchangeId!.isEmpty) &&
        widget.tradableExchangeIds.length != 1) {
      showAppToast(
        context,
        description:
            'Autopilot needs a default portfolio. Pick one, or turn Autopilot off.',
        destructive: true,
      );
      return;
    }
    final symbols =
        normalizeScheduleSymbols([_scheduleSymbolsController.text]);
    if (_scheduleEnabled && symbols.isEmpty) {
      showAppToast(
        context,
        description: 'Schedule needs at least one symbol.',
        destructive: true,
      );
      return;
    }
    final defaultId = _autopilotExchangeId ??
        (widget.tradableExchangeIds.length == 1
            ? widget.tradableExchangeIds.first.$1
            : null);
    Navigator.of(context).pop(
      _ConnectResult(
        provider: _provider,
        apiKey: _apiKeyController.text,
        modelId: modelId,
        baseUrl: _provider == LlmProvider.custom
            ? _baseUrlController.text.trim()
            : null,
        autopilotEnabled: _autopilotEnabled,
        autopilotExchangeId: defaultId,
        autopilotMaxNotional: notional,
        autopilotMaxOpenProposals: _maxOpen,
        scheduleEnabled: _scheduleEnabled,
        scheduleInterval: _scheduleInterval,
        scheduleSymbols: symbols,
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
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
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
                Text('Default portfolio', style: theme.textTheme.small),
                const SizedBox(height: 6),
                Text(
                  'Optional. When set, Confirm and Autopilot use this portfolio. '
                  'When none, Confirm asks each time.',
                  style: theme.textTheme.muted,
                ),
                const SizedBox(height: 8),
                if (widget.tradableExchangeIds.isEmpty)
                  Text(
                    'Practice should appear here. Try reopening the app.',
                    style: theme.textTheme.muted,
                  )
                else
                  ShadSelect<String>(
                    minWidth: double.infinity,
                    initialValue: _autopilotExchangeId ?? _nonePortfolio,
                    placeholder: const Text('Choose on Confirm'),
                    options: [
                      if (widget.tradableExchangeIds.length > 1)
                        const ShadOption(
                          value: _nonePortfolio,
                          child: Text('None — choose on Confirm'),
                        ),
                      for (final e in widget.tradableExchangeIds)
                        ShadOption(value: e.$1, child: Text(e.$2)),
                    ],
                    selectedOptionBuilder: (context, value) {
                      if (value == _nonePortfolio) {
                        return const Text('None — choose on Confirm');
                      }
                      for (final e in widget.tradableExchangeIds) {
                        if (e.$1 == value) return Text(e.$2);
                      }
                      return Text(value);
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _autopilotExchangeId =
                            value == _nonePortfolio ? null : value;
                      });
                    },
                  ),
                const SizedBox(height: 18),
                Text('Autopilot', style: theme.textTheme.small),
                const SizedBox(height: 6),
                Text(
                  'Off by default. When on, risk-approved suggestions submit '
                  'to the default portfolio without Confirm. Requires a '
                  'default portfolio above.',
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
              const SizedBox(height: 18),
              Text('Schedule', style: theme.textTheme.small),
              const SizedBox(height: 6),
              Text(
                'Runs while Omniscope is open on this device. '
                'Pauses in the background.',
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Enable schedule',
                      style: theme.textTheme.p,
                    ),
                  ),
                  ShadSwitch(
                    value: _scheduleEnabled,
                    onChanged: (v) => setState(() => _scheduleEnabled = v),
                  ),
                ],
              ),
              if (_scheduleEnabled) ...[
                const SizedBox(height: 12),
                Text('Interval', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadSelect<AgentScheduleInterval>(
                  minWidth: double.infinity,
                  initialValue: _scheduleInterval,
                  options: [
                    for (final interval in AgentScheduleInterval.values)
                      ShadOption(
                        value: interval,
                        child: Text(interval.label),
                      ),
                  ],
                  selectedOptionBuilder: (context, value) =>
                      Text(value.label),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _scheduleInterval = value);
                  },
                ),
                const SizedBox(height: 12),
                Text('Symbols', style: theme.textTheme.small),
                const SizedBox(height: 6),
                ShadInput(
                  controller: _scheduleSymbolsController,
                  placeholder: const Text('AAPL, BTC_USD, …'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
