import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/material_compat.dart' show SelectionArea;
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agent_pnl_service.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/models.dart';
import '../../data/agents/genkit/genkit_agent_runner.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/mandate_settings.dart';
import '../../data/settings/settings_listen_keys.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/agent_markdown_body.dart';
import '../../widgets/agent_pnl_strip.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_text.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/autopilot_status_pill.dart';
import '../../widgets/memory_status_pill.dart';
import '../../widgets/portfolio_picker_dialog.dart';
import '../../widgets/schedule_status_pill.dart';
import '../../widgets/subscreen_app_bar.dart';
import '../asset_detail/asset_detail_screen.dart';
import 'agent_chat_controller.dart';
import 'agent_schedule_coordinator.dart';

class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({
    super.key,
    required this.chatId,
    this.initialSymbol,
    this.initialExchangeId,
    this.autoRun = false,
    this.initialSide,
    this.initialQuantity,
    this.starterRoleId,
    this.onOpenMenu,
  });

  final String chatId;

  /// Optional symbol for deep-link / Investigate launches.
  final String? initialSymbol;

  /// Optional live exchange id for balance-explainer launches.
  final String? initialExchangeId;

  /// When true, send a starter on first open.
  final bool autoRun;

  final String? initialSide;
  final double? initialQuantity;

  /// Catalog role id for auto-run / preferred starter (optional).
  final String? starterRoleId;

  /// Opens the Agents chat list overlay (master–detail embedding).
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final schedule = context.read<AgentScheduleCoordinator>();
        return AgentChatController(
          chatId: chatId,
          agents: context.read<AgentsRepository>(),
          chats: context.read<AgentChatRepository>(),
          marketData: context.read<MarketDataClient>(),
          agentRunner: context.read<GenkitAgentRunner>(),
          tradeExecutor: context.read<TradeExecutor>(),
          proposals: context.read<TradeProposalRepository>(),
          activity: context.read<AgentActivityRepository>(),
          cryptoRegistry: context.read<CryptoExchangeRegistry>(),
          brokerRegistry: context.read<BrokerExchangeRegistry>(),
          dataSources: context.read<DataSourceSettings>(),
          portfolio: context.read<PortfolioRepository>(),
          secrets: context.read<EnvSecretsRepository>(),
          llmRuntime: context.read<LlmRuntimeSettings>(),
          appSettings: context.read<AgentAppSettings>(),
          favorites: context.read<FavoritesRepository>(),
          mandate: context.read<MandateSettings>(),
          agentMemory: context.read<AgentMemoryRepository>(),
          investInterestProposals:
              context.read<InvestInterestProposalRepository>(),
          scheduleInFlight: () => schedule.isInFlight,
        );
      },
      child: _AgentChatView(
        chatId: chatId,
        initialSymbol: initialSymbol,
        initialExchangeId: initialExchangeId,
        autoRun: autoRun,
        initialSide: initialSide,
        initialQuantity: initialQuantity,
        starterRoleId: starterRoleId,
        onOpenMenu: onOpenMenu,
      ),
    );
  }
}

class _AgentChatView extends StatefulWidget {
  const _AgentChatView({
    required this.chatId,
    this.initialSymbol,
    this.initialExchangeId,
    this.autoRun = false,
    this.initialSide,
    this.initialQuantity,
    this.starterRoleId,
    this.onOpenMenu,
  });

  final String chatId;
  final String? initialSymbol;
  final String? initialExchangeId;
  final bool autoRun;
  final String? initialSide;
  final double? initialQuantity;
  final String? starterRoleId;
  final VoidCallback? onOpenMenu;

  @override
  State<_AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends State<_AgentChatView> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scrollController = ScrollController();
  var _autoRunStarted = false;
  var _draftLaunchStarted = false;
  String? _selectedStarterRoleId;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _composerFocus.onKeyEvent = _onComposerKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoRun();
      _maybeDraftLaunch();
    });
  }

  void _onComposerChanged() {
    if (_selectedStarterRoleId == null) return;
    if (_composer.text.trim().isNotEmpty) return;
    setState(() => _selectedStarterRoleId = null);
  }

  /// Enter sends; Shift+Enter inserts a newline (multiline composer).
  KeyEventResult _onComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!mounted) return KeyEventResult.handled;
    final controller = context.read<AgentChatController>();
    if (!controller.sending && controller.hasLlmEndpoint) {
      _sendComposer();
    }
    return KeyEventResult.handled;
  }

  Future<void> _maybeAutoRun() async {
    if (_autoRunStarted || !mounted) return;
    if (!widget.autoRun) return;
    final roleId = widget.starterRoleId ?? 'marketResearch';
    final symbol = widget.initialSymbol?.trim() ?? '';
    final canSkipSymbol = AgentRolePrompts.allowsRunWithoutSymbol(roleId);
    if (symbol.isEmpty && !canSkipSymbol) return;
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    _autoRunStarted = true;
    final result = await controller.sendStarter(
      roleId: roleId,
      symbol: symbol,
      exchangeId: widget.initialExchangeId,
      side: widget.initialSide,
      quantity: widget.initialQuantity,
    );
    await _handleSendResult(result);
  }

  /// Prefill the composer from a deep-link launch without sending.
  void _maybeDraftLaunch() {
    if (_draftLaunchStarted || !mounted) return;
    if (widget.autoRun) return;
    final roleId = widget.starterRoleId?.trim();
    if (roleId == null || roleId.isEmpty) return;
    _draftLaunchStarted = true;
    _draftStarter(roleId);
  }

  @override
  void dispose() {
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleSendResult(AgentChatSendResult result) async {
    _scrollToBottom();
    if (!mounted) return;
    if (result is AgentChatSendFailed) {
      showAppToast(
        context,
        title: result.suggestConnections ? 'LLM connection issue' : null,
        description: result.message,
        destructive: true,
      );
      if (result.suggestConnections) {
        context.read<ShellNavigationController>().goToSettings(
              sectionId: 'connections',
            );
      }
    } else if (result is AgentChatSendBlockedNoExchange) {
      showAppToast(
        context,
        title: 'No trade target',
        description:
            'Practice should always be available. Try reopening the app, or '
            'add a live exchange under Settings → Data sources.',
        destructive: true,
      );
    } else if (result is AgentChatSendBlockedNoLlm) {
      showAppToast(
        context,
        title: 'Add an LLM key',
        description:
            'Add a provider key under Settings → Connections, then try again.',
        destructive: true,
      );
      context.read<ShellNavigationController>().goToSettings(
            sectionId: 'connections',
          );
    }
  }

  Future<void> _sendComposer() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    final roleId = _selectedStarterRoleId;
    if (roleId != null) {
      final placeholderError =
          AgentRolePrompts.unresolvedDraftPlaceholderMessage(
        roleId: roleId,
        text: text,
      );
      if (placeholderError != null) {
        showAppToast(
          context,
          description: placeholderError,
          destructive: true,
        );
        return;
      }
      _composer.clear();
      setState(() => _selectedStarterRoleId = null);
      final result = await controller.sendStarter(
        roleId: roleId,
        content: text,
        symbol: widget.initialSymbol?.trim() ?? '',
        exchangeId: widget.initialExchangeId,
        side: widget.initialSide,
        quantity: widget.initialQuantity,
      );
      await _handleSendResult(result);
      return;
    }
    _composer.clear();
    final result = await controller.sendFreeform(
      text,
      exchangeId: widget.initialExchangeId,
    );
    await _handleSendResult(result);
  }

  void _draftStarter(String roleId) {
    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: roleId,
      symbol: widget.initialSymbol?.trim() ?? '',
      side: widget.initialSide,
      quantity: widget.initialQuantity,
    );
    setState(() => _selectedStarterRoleId = roleId);
    _composer.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _composerFocus.requestFocus();
  }

  Future<void> _copyToClipboard(
    String text, {
    required String description,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!mounted) return;
    showAppToast(
      context,
      title: 'Copied',
      description: description,
    );
  }

  Future<void> _copyChat(AgentChatThread thread) async {
    await _copyToClipboard(
      thread.plainTextExchange,
      description: 'Full chat copied to clipboard.',
    );
  }

  Future<void> _toggleAutopilot(AgentChatThread thread) async {
    final next = !thread.autopilotEnabled;
    final chats = context.read<AgentChatRepository>();
    if (next) {
      final block = chats.autopilotEnableBlockReason(thread.chatId);
      if (block != null) {
        showAppToast(context, description: block);
        return;
      }
    }
    await chats.setAutopilotEnabled(thread.chatId, enabled: next);
    var appliedIi = 0;
    if (next && mounted) {
      appliedIi = await context
          .read<AgentChatController>()
          .applyPendingAutopilotInvestInterest();
    }
    if (!mounted) return;
    showAppToast(
      context,
      description: next
          ? (appliedIi > 0
              ? 'Autopilot on · applied $appliedIi Invest interest '
                  '${appliedIi == 1 ? 'add' : 'adds'}'
              : 'Autopilot on for this chat')
          : 'Autopilot off for this chat',
    );
  }

  Future<void> _toggleMemory(AgentChatThread thread) async {
    final next = !thread.memoryEnabled;
    await context.read<AgentChatRepository>().setMemoryEnabled(
          thread.chatId,
          enabled: next,
        );
    if (!mounted) return;
    showAppToast(
      context,
      description: next
          ? 'Memory on for this chat'
          : 'Memory off for this chat',
    );
  }

  Future<void> _confirmProposal(TradeProposal proposal) async {
    final controller = context.read<AgentChatController>();
    String? targetId = controller.resolveConfirmPortfolioId();
    if (targetId == null) {
      targetId = await showPortfolioPickerDialog(
        context,
        venues: controller.tradableVenues,
      );
      if (targetId == null || !mounted) return;
    }
    String label = targetId;
    for (final v in controller.tradableVenues) {
      if (v.id == targetId) {
        label = v.displayName;
        break;
      }
    }
    final err = await controller.confirmProposal(
      proposal.id,
      targetPortfolioId: targetId,
    );
    if (!mounted) return;
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    } else {
      showAppToast(
        context,
        description: 'Submitted to $label for ${proposal.symbol}',
      );
    }
  }

  Future<void> _dismissProposal(TradeProposal proposal) async {
    final err =
        await context.read<AgentChatController>().dismissProposal(proposal.id);
    if (!mounted) return;
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    }
  }

  Future<void> _confirmInvestInterest(InvestInterestProposal proposal) async {
    final err = await context
        .read<AgentChatController>()
        .confirmInvestInterestProposal(proposal.id);
    if (!mounted) return;
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    } else {
      showAppToast(context, description: 'Invest interest updated');
    }
  }

  Future<void> _dismissInvestInterest(InvestInterestProposal proposal) async {
    final err = await context
        .read<AgentChatController>()
        .dismissInvestInterestProposal(proposal.id);
    if (!mounted) return;
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final thread =
        context.watch<AgentChatRepository>().threadFor(widget.chatId);
    final controller = context.watch<AgentChatController>();
    final proposals = context.watch<TradeProposalRepository>();
    final investInterest =
        context.watch<InvestInterestProposalRepository>();
    context.select<EnvSecretsRepository, String>(exchangeCredsFingerprint);
    context.select<DataSourceSettings, String>(dataSourceFingerprint);
    final sending = controller.sending;
    final ready = controller.hasLlmEndpoint;
    final starters = controller.enabledRoles;

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubscreenAppBar(
              title: thread.title,
              showBack: false,
              onOpenMenu: widget.onOpenMenu,
              titleAlign: TextAlign.start,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScheduleStatusPill(chatId: widget.chatId),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppTooltip(
                        message: thread.autopilotEnabled
                            ? 'Autopilot on — tap to require Confirm'
                            : 'Autopilot off — tap to auto-apply in this chat',
                        child: AutopilotStatusPill(
                          enabled: thread.autopilotEnabled,
                          onTap: () => _toggleAutopilot(thread),
                        ),
                      ),
                      AppTooltip(
                        message: thread.memoryEnabled
                            ? 'Memory on — shared facts for this chat'
                            : 'Memory off — this chat ignores shared memory',
                        child: MemoryStatusPill(
                          enabled: thread.memoryEnabled,
                          onTap: () => _toggleMemory(thread),
                        ),
                      ),
                    ],
                  ),
                  if (thread.messages.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    AppTooltip(
                      message: 'Copy chat',
                      child: ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        width: 36,
                        height: 36,
                        padding: EdgeInsets.zero,
                        onPressed: () => _copyChat(thread),
                        child: const Icon(LucideIcons.copy, size: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                ready
                    ? (context.watch<AgentAppSettings>().isScheduleChat(
                            widget.chatId,
                          )
                        ? 'Scheduled research reports here · Confirm still '
                            'gates fills. Turn on Autopilot on this chat to '
                            'auto-apply risk-approved suggestions.'
                        : (thread.autopilotEnabled
                            ? 'Autopilot is on for this chat: risk-approved '
                                'trades and add-only Invest interest may apply '
                                'without Confirm. Other chats still need Confirm.'
                            : 'Omniscope routes specialists for you. Confirm still '
                                'gates trade and Invest interest suggestions.'))
                    : 'Add an LLM API key under Settings → Connections to chat.',
                style: theme.textTheme.muted,
              ),
            ),
            Builder(
              builder: (context) {
                final symbol = AgentPnlService.latestFilledSymbolForChat(
                  proposals: proposals.proposals,
                  chatId: widget.chatId,
                );
                if (symbol == null) return const SizedBox.shrink();
                final summary = AgentPnlService.summaryForChatSymbol(
                  proposals: proposals.proposals,
                  chatId: widget.chatId,
                  symbol: symbol,
                );
                if (!summary.hasActivity) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AgentPnlStrip(
                    summary: summary,
                    leading: 'This chat',
                  ),
                );
              },
            ),
            Expanded(
              child: thread.messages.isEmpty
                  ? (ready && starters.isNotEmpty
                      ? _StarterPromptList(
                          roles: starters,
                          enabled: !sending,
                          selectedRoleId: _selectedStarterRoleId,
                          onSelect: _draftStarter,
                        )
                      : AppEmptyView(
                          ready
                              ? 'Start a conversation — ask anything below.'
                              : 'Configure a provider key first, then come back.',
                        ))
                  // Own [SelectionArea] so message text stays selectable even
                  // though the tab route also wraps chrome (composer / sidebar)
                  // in a parent SelectionArea that competes for gestures.
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: thread.messages.length,
                        itemBuilder: (context, index) {
                          final message = thread.messages[index];
                          TradeProposal? tradeProposal;
                          InvestInterestProposal? investProposal;
                          final pid = message.proposalId;
                          if (pid != null) {
                            tradeProposal = proposals.byId(pid);
                            investProposal = investInterest.byId(pid);
                          }
                          final tradePending = tradeProposal != null &&
                              tradeProposal.status ==
                                  TradeProposalStatus.pending;
                          final investPending = investProposal != null &&
                              investProposal.status ==
                                  InvestInterestProposalStatus.pending;
                          return _ChatBubble(
                            message: message,
                            proposal: tradeProposal,
                            investInterestProposal: investProposal,
                            busy: controller.actingOnProposal,
                            onConfirm: tradePending
                                ? () => _confirmProposal(tradeProposal!)
                                : investPending
                                    ? () => _confirmInvestInterest(
                                          investProposal!,
                                        )
                                    : null,
                            onDismiss: tradePending
                                ? () => _dismissProposal(tradeProposal!)
                                : investPending
                                    ? () => _dismissInvestInterest(
                                          investProposal!,
                                        )
                                    : null,
                          );
                        },
                      ),
                    ),
            ),
            // Keep composer out of the route-level SelectionArea so
            // EditableText does not steal message selection.
            SelectionContainer.disabled(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sending)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: AppProgress(),
                    ),
                  if (thread.focusSymbols.isNotEmpty)
                    _FocusSymbolChips(
                      symbols: thread.focusSymbols,
                      onUnpin: (symbol) => context
                          .read<AgentChatRepository>()
                          .unpinFocusSymbols(widget.chatId, [symbol]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ShadInput(
                            controller: _composer,
                            focusNode: _composerFocus,
                            placeholder: const Text('Message…'),
                            minLines: 2,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              if (!sending && ready) _sendComposer();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          child: ShadButton(
                            enabled: !sending && ready,
                            onPressed: _sendComposer,
                            child: const Text('Send'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Focus symbols for this chat — shown just above the composer.
class _FocusSymbolChips extends StatelessWidget {
  const _FocusSymbolChips({
    required this.symbols,
    required this.onUnpin,
  });

  final List<String> symbols;
  final ValueChanged<String> onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'In this chat',
            style: theme.textTheme.muted.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final symbol in symbols)
                _FocusSymbolChip(
                  symbol: symbol,
                  onUnpin: () => onUnpin(symbol),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusSymbolChip extends StatelessWidget {
  const _FocusSymbolChip({
    required this.symbol,
    required this.onUnpin,
  });

  final String symbol;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 2, right: 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () {
              pushFadePage(context, AssetDetailScreen(symbol: symbol));
            },
            child: Text(
              symbol,
              style: theme.textTheme.small.copyWith(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AppTooltip(
            message: 'Unpin $symbol',
            child: ShadButton.ghost(
              size: ShadButtonSize.sm,
              width: 24,
              height: 24,
              padding: EdgeInsets.zero,
              onPressed: onUnpin,
              child: Icon(
                LucideIcons.x,
                size: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable starter options for empty chats — tap drafts the composer.
class _StarterPromptList extends StatelessWidget {
  const _StarterPromptList({
    required this.roles,
    required this.enabled,
    required this.selectedRoleId,
    required this.onSelect,
  });

  final List<AgentRoleDefinition> roles;
  final bool enabled;
  final String? selectedRoleId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth >= 720 ? 520.0 : double.infinity;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a starter',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap a starter, edit if needed, then Send. Market '
                      'research can explore a topic; Trade check needs a '
                      'ticker.',
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < roles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      _StarterPromptOption(
                        roleId: roles[i].id,
                        enabled: enabled,
                        selected: selectedRoleId == roles[i].id,
                        onSelect: () => onSelect(roles[i].id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StarterPromptOption extends StatelessWidget {
  const _StarterPromptOption({
    required this.roleId,
    required this.enabled,
    required this.selected,
    required this.onSelect,
  });

  final String roleId;
  final bool enabled;
  final bool selected;
  final VoidCallback onSelect;

  IconData get _icon => switch (roleId) {
        'marketResearch' => LucideIcons.search,
        'liveBalanceExplainer' => LucideIcons.wallet,
        'portfolioGuide' => LucideIcons.pieChart,
        'intradayTrading' => LucideIcons.activity,
        'cryptoSpotGuide' => LucideIcons.bitcoin,
        'marketsLiteracy' => LucideIcons.bookOpen,
        _ => LucideIcons.messageSquare,
      };

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = AgentRolePrompts.runChipLabel(roleId);
    final description = AgentRolePrompts.runChipDescription(roleId);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      hint: description,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onSelect : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? theme.colorScheme.secondary : null,
                  borderRadius: theme.radius,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.border,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.secondaryForeground
                                  .withValues(alpha: 0.12)
                              : theme.colorScheme.secondary,
                          borderRadius: theme.radius,
                        ),
                        child: Icon(
                          _icon,
                          size: 14,
                          color: selected
                              ? theme.colorScheme.secondaryForeground
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.p.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              description,
                              style: theme.textTheme.small.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected
                            ? LucideIcons.check
                            : LucideIcons.chevronRight,
                        size: 16,
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                            : theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.proposal,
    this.investInterestProposal,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final AgentChatMessage message;
  final TradeProposal? proposal;
  final InvestInterestProposal? investInterestProposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  Future<void> _copyAnswer(BuildContext context) async {
    final text = message.content.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Copied',
      description: 'Answer copied to clipboard.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUser = message.role == AgentChatRole.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;
    final fg = isUser
        ? theme.colorScheme.primaryForeground
        : theme.colorScheme.secondaryForeground;
    final showAssistantMeta = !isUser &&
        (message.content.trim().isNotEmpty ||
            message.generationMetaLabel != null);

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.only(
                top: 6,
                bottom: showAssistantMeta ? 2 : 6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.border),
                boxShadow: [
                  BoxShadow(
                    color: BrandColors.shadowOf(context),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DefaultSelectionStyle(
                // Brand selection blends into secondary bubbles; tint with the
                // bubble foreground so drag-select stays visible on both sides.
                selectionColor: fg.withValues(alpha: 0.35),
                child: MouseRegion(
                  cursor: SystemMouseCursors.text,
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (message.kind == AgentChatMessageKind.run && isUser)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Run',
                            style: theme.textTheme.small.copyWith(
                              color: fg.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (isUser)
                        Text(
                          message.content,
                          style: theme.textTheme.small.copyWith(
                            color: fg,
                            height: 1.4,
                          ),
                        )
                      else
                        AgentMarkdownBody(
                          data: message.content,
                          style: theme.textTheme.small.copyWith(
                            color: fg,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (showAssistantMeta)
              SelectionContainer.disabled(
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Row(
                    children: [
                      if (message.content.trim().isNotEmpty)
                        AppTooltip(
                          message: 'Copy answer',
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            width: 28,
                            height: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () => _copyAnswer(context),
                            child: Icon(
                              LucideIcons.copy,
                              size: 14,
                              color: theme.colorScheme.mutedForeground,
                            ),
                          ),
                        ),
                      if (message.generationMetaLabel != null) ...[
                        if (message.content.trim().isNotEmpty)
                          const SizedBox(width: 2),
                        Flexible(
                          child: AppEllipsisText(
                            message.generationMetaLabel!,
                            maxLines: 1,
                            style: theme.textTheme.muted.copyWith(fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // Keep Confirm / Dismiss out of the chat SelectionArea so taps
            // are not swallowed by text-selection gestures.
            if (proposal != null)
              SelectionContainer.disabled(
                child: _TradeProposalCard(
                  proposal: proposal!,
                  onConfirm: onConfirm,
                  onDismiss: onDismiss,
                  busy: busy,
                ),
              ),
            if (investInterestProposal != null)
              SelectionContainer.disabled(
                child: _InvestInterestProposalCard(
                  proposal: investInterestProposal!,
                  onConfirm: onConfirm,
                  onDismiss: onDismiss,
                  busy: busy,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _portfolioLabel(BuildContext context, String portfolioId) {
  try {
    final venues = context.read<TradeExecutor>().tradableVenues;
    for (final v in venues) {
      if (v.id == portfolioId) return v.displayName;
    }
  } catch (_) {
    // Provider may be absent in isolated tests.
  }
  if (portfolioId == 'practice') return 'Practice';
  return portfolioId;
}

class _TradeProposalCard extends StatelessWidget {
  const _TradeProposalCard({
    required this.proposal,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final TradeProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final riskColor = proposal.riskApproved
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
            style: theme.textTheme.large,
          ),
          const SizedBox(height: 4),
          Text(
            'Portfolio: ${_portfolioLabel(context, proposal.exchangeId)} · '
            '${proposal.status.label}'
            '${proposal.autopilot ? ' · Autopilot' : ''}',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 6),
          Text(
            proposal.riskApproved ? 'Risk approved' : 'Risk veto',
            style: theme.textTheme.small.copyWith(
              color: riskColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (proposal.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(proposal.rationale, style: theme.textTheme.small),
          ],
          if (proposal.executionError != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.executionError!,
              style: theme.textTheme.small.copyWith(
                color: BrandColors.lossOf(context),
              ),
            ),
          ],
          if (proposal.orderId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Order id: ${proposal.orderId}',
              style: theme.textTheme.small,
            ),
          ],
          if (onConfirm != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onDismiss != null)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ShadButton.outline(
                        enabled: !busy,
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
                      ),
                    ),
                  ),
                if (onConfirm != null && onDismiss != null)
                  const SizedBox(width: 8),
                if (onConfirm != null)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ShadButton(
                        enabled: !busy,
                        onPressed: onConfirm,
                        child: const Text('Confirm'),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InvestInterestProposalCard extends StatelessWidget {
  const _InvestInterestProposalCard({
    required this.proposal,
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final InvestInterestProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(proposal.summaryLabel, style: theme.textTheme.large),
          const SizedBox(height: 4),
          Text(
            'Invest interest · ${proposal.status.label}',
            style: theme.textTheme.muted,
          ),
          if (onConfirm != null) ...[
            const SizedBox(height: 4),
            Text(
              'Tap Confirm below to apply this change.',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (proposal.add.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Add: ${proposal.add.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.remove.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remove: ${proposal.remove.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.setSymbols != null) ...[
            const SizedBox(height: 4),
            Text(
              'Set to: ${proposal.setSymbols!.join(', ')}',
              style: theme.textTheme.small,
            ),
          ],
          if (proposal.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(proposal.rationale, style: theme.textTheme.small),
          ],
          if (proposal.applyError != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.applyError!,
              style: theme.textTheme.small.copyWith(
                color: BrandColors.lossOf(context),
              ),
            ),
          ],
          if (onConfirm != null || onDismiss != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onDismiss != null)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ShadButton.outline(
                        enabled: !busy,
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
                      ),
                    ),
                  ),
                if (onConfirm != null && onDismiss != null)
                  const SizedBox(width: 8),
                if (onConfirm != null)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ShadButton(
                        enabled: !busy,
                        onPressed: onConfirm,
                        child: const Text('Confirm'),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
