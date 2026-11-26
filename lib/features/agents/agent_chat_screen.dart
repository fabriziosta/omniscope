import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/material_compat.dart' show SelectionArea;
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/models.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agent_pnl_service.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
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
import '../../data/settings/settings_listen_keys.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/agent_pnl_strip.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/portfolio_picker_dialog.dart';
import '../../widgets/schedule_status_pill.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'agent_chat_bubble.dart';
import 'agent_chat_controller.dart';
import 'agent_focus_symbol_chips.dart';
import 'agent_starter_chips.dart';
import 'agent_chat_options_menu.dart';
import 'agent_schedule_coordinator.dart';

String _tradeProposalActivityFingerprint(
  List<TradeProposal> proposals,
  String chatId,
) {
  final buf = StringBuffer('$chatId:${proposals.length}');
  for (final p in proposals) {
    if (p.chatId != chatId) continue;
    buf
      ..write('|')
      ..write(p.id)
      ..write(':')
      ..write(p.status.index)
      ..write(':')
      ..write(p.symbol);
  }
  return buf.toString();
}

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
    this.onDeleted,
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

  /// Called after this chat is deleted from the shared options menu.
  final VoidCallback? onDeleted;

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
        onDeleted: onDeleted,
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
    this.onDeleted,
  });

  final String chatId;
  final String? initialSymbol;
  final String? initialExchangeId;
  final bool autoRun;
  final String? initialSide;
  final double? initialQuantity;
  final String? starterRoleId;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onDeleted;

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
            'Add a provider key under Settings → Agents, then try again.',
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
    context.select<EnvSecretsRepository, String>(exchangeCredsFingerprint);
    context.select<DataSourceSettings, String>(dataSourceFingerprint);

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AgentChatAppBar(
              chatId: widget.chatId,
              onOpenMenu: widget.onOpenMenu,
              onDeleted: widget.onDeleted,
            ),
            _AgentChatStatusHint(chatId: widget.chatId),
            _AgentChatPnlStrip(chatId: widget.chatId),
            Expanded(
              child: _AgentChatMessageArea(
                chatId: widget.chatId,
                scrollController: _scrollController,
                selectedStarterRoleId: _selectedStarterRoleId,
                onDraftStarter: _draftStarter,
                onConfirmProposal: _confirmProposal,
                onDismissProposal: _dismissProposal,
                onConfirmInvestInterest: _confirmInvestInterest,
                onDismissInvestInterest: _dismissInvestInterest,
              ),
            ),
            SelectionContainer.disabled(
              child: _AgentChatComposer(
                chatId: widget.chatId,
                composer: _composer,
                composerFocus: _composerFocus,
                onSend: _sendComposer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentChatAppBar extends StatelessWidget {
  const _AgentChatAppBar({
    required this.chatId,
    this.onOpenMenu,
    this.onDeleted,
  });

  final String chatId;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final thread = context.select<AgentChatRepository, AgentChatThread>(
      (r) => r.threadFor(chatId),
    );
    return SubscreenAppBar(
      title: thread.title,
      showBack: false,
      onOpenMenu: onOpenMenu,
      titleAlign: TextAlign.start,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScheduleStatusPill(chatId: chatId),
          AgentChatOptionsMenu(
            thread: thread,
            onDeleted: onDeleted,
          ),
        ],
      ),
    );
  }
}

class _AgentChatStatusHint extends StatelessWidget {
  const _AgentChatStatusHint({required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final ready = context.select<AgentChatController, bool>(
      (c) => c.hasLlmEndpoint,
    );
    final isSchedule = context.select<AgentAppSettings, bool>(
      (s) => s.isScheduleChat(chatId),
    );
    final autopilot = context.select<AgentChatRepository, bool>(
      (r) => r.threadFor(chatId).autopilotEnabled,
    );

    final copy = !ready
        ? 'Add an LLM API key under Settings → Agents to chat.'
        : isSchedule
            ? 'Scheduled research reports here · Confirm still '
                'gates fills. Turn on Autopilot on this chat to '
                'auto-apply risk-approved suggestions.'
            : autopilot
                ? 'Autopilot is on for this chat: risk-approved '
                    'trades and add-only Invest interest may apply '
                    'without Confirm. Other chats still need Confirm.'
                : 'Omniscope routes specialists for you. Confirm still '
                    'gates trade and Invest interest suggestions.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(copy, style: theme.textTheme.muted),
    );
  }
}

class _AgentChatPnlStrip extends StatelessWidget {
  const _AgentChatPnlStrip({required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) {
    context.select<TradeProposalRepository, String>(
      (r) => _tradeProposalActivityFingerprint(r.proposals, chatId),
    );
    final proposals = context.read<TradeProposalRepository>().proposals;
    final symbol = AgentPnlService.latestFilledSymbolForChat(
      proposals: proposals,
      chatId: chatId,
    );
    if (symbol == null) return const SizedBox.shrink();
    final summary = AgentPnlService.summaryForChatSymbol(
      proposals: proposals,
      chatId: chatId,
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
  }
}

class _AgentChatMessageArea extends StatelessWidget {
  const _AgentChatMessageArea({
    required this.chatId,
    required this.scrollController,
    required this.selectedStarterRoleId,
    required this.onDraftStarter,
    required this.onConfirmProposal,
    required this.onDismissProposal,
    required this.onConfirmInvestInterest,
    required this.onDismissInvestInterest,
  });

  final String chatId;
  final ScrollController scrollController;
  final String? selectedStarterRoleId;
  final void Function(String roleId) onDraftStarter;
  final Future<void> Function(TradeProposal) onConfirmProposal;
  final Future<void> Function(TradeProposal) onDismissProposal;
  final Future<void> Function(InvestInterestProposal) onConfirmInvestInterest;
  final Future<void> Function(InvestInterestProposal) onDismissInvestInterest;

  @override
  Widget build(BuildContext context) {
    final messages = context.select<AgentChatRepository, List<AgentChatMessage>>(
      (r) => r.threadFor(chatId).messages,
    );
    final ready = context.select<AgentChatController, bool>(
      (c) => c.hasLlmEndpoint,
    );
    final sending = context.select<AgentChatController, bool>(
      (c) => c.sending,
    );
    // Fingerprint only — enabledRoles allocates a new List every call, which
    // would trip select's == and rebuild forever (pumpAndSettle hang).
    context.select<AgentChatController, String>(
      (c) => c.enabledRoles.map((r) => r.id).join('\u0001'),
    );
    final starters = context.read<AgentChatController>().enabledRoles;

    if (messages.isEmpty) {
      if (ready && starters.isNotEmpty) {
        return StarterPromptList(
          roles: starters,
          enabled: !sending,
          selectedRoleId: selectedStarterRoleId,
          onSelect: onDraftStarter,
        );
      }
      return AppEmptyView(
        ready
            ? 'Start a conversation — ask anything below.'
            : 'Configure a provider key first, then come back.',
      );
    }

    return SelectionArea(
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _AgentChatMessageTile(
            message: message,
            onConfirmProposal: onConfirmProposal,
            onDismissProposal: onDismissProposal,
            onConfirmInvestInterest: onConfirmInvestInterest,
            onDismissInvestInterest: onDismissInvestInterest,
          );
        },
      ),
    );
  }
}

class _AgentChatMessageTile extends StatelessWidget {
  const _AgentChatMessageTile({
    required this.message,
    required this.onConfirmProposal,
    required this.onDismissProposal,
    required this.onConfirmInvestInterest,
    required this.onDismissInvestInterest,
  });

  final AgentChatMessage message;
  final Future<void> Function(TradeProposal) onConfirmProposal;
  final Future<void> Function(TradeProposal) onDismissProposal;
  final Future<void> Function(InvestInterestProposal) onConfirmInvestInterest;
  final Future<void> Function(InvestInterestProposal) onDismissInvestInterest;

  @override
  Widget build(BuildContext context) {
    final proposalId = message.proposalId;
    TradeProposal? tradeProposal;
    InvestInterestProposal? investProposal;
    if (proposalId != null) {
      tradeProposal = context.select<TradeProposalRepository, TradeProposal?>(
        (r) => r.byId(proposalId),
      );
      investProposal =
          context.select<InvestInterestProposalRepository, InvestInterestProposal?>(
        (r) => r.byId(proposalId),
      );
    }
    final busy = context.select<AgentChatController, bool>(
      (c) => c.actingOnProposal,
    );

    final tradePending = tradeProposal != null &&
        tradeProposal.status == TradeProposalStatus.pending;
    final investPending = investProposal != null &&
        investProposal.status == InvestInterestProposalStatus.pending;

    return ChatBubble(
      key: ValueKey(message.id),
      message: message,
      proposal: tradeProposal,
      investInterestProposal: investProposal,
      busy: busy,
      onConfirm: tradePending
          ? () => onConfirmProposal(tradeProposal!)
          : investPending
              ? () => onConfirmInvestInterest(investProposal!)
              : null,
      onDismiss: tradePending
          ? () => onDismissProposal(tradeProposal!)
          : investPending
              ? () => onDismissInvestInterest(investProposal!)
              : null,
    );
  }
}

class _AgentChatComposer extends StatelessWidget {
  const _AgentChatComposer({
    required this.chatId,
    required this.composer,
    required this.composerFocus,
    required this.onSend,
  });

  final String chatId;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final sending = context.select<AgentChatController, bool>(
      (c) => c.sending,
    );
    final ready = context.select<AgentChatController, bool>(
      (c) => c.hasLlmEndpoint,
    );
    final focusSymbols = context.select<AgentChatRepository, List<String>>(
      (r) => r.threadFor(chatId).focusSymbols,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sending)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AppProgress(),
          ),
        if (focusSymbols.isNotEmpty) FocusSymbolChips(symbols: focusSymbols),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ShadInput(
                  controller: composer,
                  focusNode: composerFocus,
                  placeholder: const Text('Message…'),
                  minLines: 2,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!sending && ready) onSend();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ShadButton(
                  enabled: !sending && ready,
                  onPressed: onSend,
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
