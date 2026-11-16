import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
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
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/portfolio_picker_dialog.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'agent_chat_controller.dart';

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
    this.showBack = true,
    this.onBack,
    this.backLabel = 'Agents',
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

  /// When false, hide Back (wide master–detail). Narrow uses [onBack].
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AgentChatController(
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
        investInterestProposals:
            context.read<InvestInterestProposalRepository>(),
      ),
      child: _AgentChatView(
        chatId: chatId,
        initialSymbol: initialSymbol,
        initialExchangeId: initialExchangeId,
        autoRun: autoRun,
        initialSide: initialSide,
        initialQuantity: initialQuantity,
        starterRoleId: starterRoleId,
        showBack: showBack,
        onBack: onBack,
        backLabel: backLabel,
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
    this.showBack = true,
    this.onBack,
    this.backLabel = 'Agents',
  });

  final String chatId;
  final String? initialSymbol;
  final String? initialExchangeId;
  final bool autoRun;
  final String? initialSide;
  final double? initialQuantity;
  final String? starterRoleId;
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<_AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends State<_AgentChatView> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  var _autoRunStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoRun());
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

  @override
  void dispose() {
    _composer.dispose();
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
        description: result.message,
        destructive: true,
      );
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

  Future<void> _sendFreeform() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    _composer.clear();
    final result = await controller.sendFreeform(
      text,
      exchangeId: widget.initialExchangeId,
    );
    await _handleSendResult(result);
  }

  Future<void> _runStarter(String roleId) async {
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    if (roleId == 'intradayTrading' && !controller.hasTradableExchange) {
      await _handleSendResult(const AgentChatSendBlockedNoExchange());
      return;
    }
    if (AgentRolePrompts.allowsRunWithoutSymbol(roleId)) {
      final sendResult = await controller.sendStarter(
        roleId: roleId,
        symbol: widget.initialSymbol?.trim() ?? '',
        exchangeId: widget.initialExchangeId,
        side: widget.initialSide,
        quantity: widget.initialQuantity,
      );
      await _handleSendResult(sendResult);
      return;
    }
    final result = await showShadDialog<_RunSheetResult>(
      context: context,
      builder: (context) => _RunAgentDialog(
        roleId: roleId,
        initialSymbol: widget.initialSymbol,
      ),
    );
    if (result == null || !mounted) return;
    final sendResult = await controller.sendStarter(
      roleId: roleId,
      symbol: result.symbol,
      exchangeId: widget.initialExchangeId,
      side: result.side,
      quantity: result.quantity,
    );
    await _handleSendResult(sendResult);
  }

  Future<void> _confirmClear() async {
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear this chat?',
      description:
          'Removes the saved conversation on this device. '
          'This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (ok && mounted) {
      await context.read<AgentChatController>().clearThread();
    }
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
              showBack: widget.showBack,
              onBack: widget.onBack,
              backLabel: widget.backLabel,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thread.messages.isNotEmpty)
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
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: sending ? null : _confirmClear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                ready
                    ? 'Omniscope routes specialists for you. Confirm still '
                        'gates trade and Invest interest suggestions.'
                    : 'Add an LLM API key under Settings → Connections to chat.',
                style: theme.textTheme.muted,
              ),
            ),
            Expanded(
              child: thread.messages.isEmpty
                  ? AppEmptyView(
                      ready
                          ? 'Start a conversation — ask anything, or tap a '
                              'starter prompt below.'
                          : 'Configure a provider key first, then come back.',
                    )
                  : ListView.builder(
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
                            tradeProposal.status == TradeProposalStatus.pending;
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
                                  ? () =>
                                      _confirmInvestInterest(investProposal!)
                                  : null,
                          onDismiss: tradePending
                              ? () => _dismissProposal(tradeProposal!)
                              : investPending
                                  ? () =>
                                      _dismissInvestInterest(investProposal!)
                                  : null,
                        );
                      },
                    ),
            ),
            if (sending)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: AppProgress(),
              ),
            if (ready &&
                starters.isNotEmpty &&
                thread.messages.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (var i = 0; i < starters.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: !sending,
                        onPressed: () => _runStarter(starters[i].id),
                        child: Text(
                          AgentRolePrompts.runChipLabel(starters[i].id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _composer,
                      placeholder: const Text('Message…'),
                      onSubmitted: (_) {
                        if (!sending && ready) _sendFreeform();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ShadButton(
                      enabled: !sending && ready,
                      onPressed: _sendFreeform,
                      child: const Text('Send'),
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
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                      style: theme.textTheme.p.copyWith(color: fg),
                    )
                  else
                    AgentMarkdownBody(
                      data: message.content,
                      style: theme.textTheme.p.copyWith(color: fg),
                    ),
                ],
              ),
            ),
            if (showAssistantMeta)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                      Text(
                        message.generationMetaLabel!,
                        style: theme.textTheme.muted.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            if (proposal != null)
              _TradeProposalCard(
                proposal: proposal!,
                onConfirm: onConfirm,
                onDismiss: onDismiss,
                busy: busy,
              ),
            if (investInterestProposal != null)
              _InvestInterestProposalCard(
                proposal: investInterestProposal!,
                onConfirm: onConfirm,
                onDismiss: onDismiss,
                busy: busy,
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

class _RunSheetResult {
  const _RunSheetResult({
    required this.symbol,
    this.side,
    this.quantity,
  });

  final String symbol;
  final String? side;
  final double? quantity;
}

class _RunAgentDialog extends StatefulWidget {
  const _RunAgentDialog({
    required this.roleId,
    this.initialSymbol,
  });

  final String roleId;
  final String? initialSymbol;

  @override
  State<_RunAgentDialog> createState() => _RunAgentDialogState();
}

class _RunAgentDialogState extends State<_RunAgentDialog> {
  late final TextEditingController _symbol;
  final _qty = TextEditingController();
  String _side = 'buy';

  bool get _isTrading =>
      widget.roleId == 'intradayTrading';

  @override
  void initState() {
    super.initState();
    _symbol = TextEditingController(
      text: widget.initialSymbol?.trim().toUpperCase() ?? '',
    );
  }

  @override
  void dispose() {
    _symbol.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    double? qty;
    if (_isTrading && _qty.text.trim().isNotEmpty) {
      qty = double.tryParse(_qty.text.trim());
    }
    Navigator.of(context).pop(
      _RunSheetResult(
        symbol: symbol,
        side: _isTrading ? _side : null,
        quantity: qty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: Text(AgentRolePrompts.runChipLabel(widget.roleId)),
      description: Text(
        AgentRolePrompts.supportsTradeProposals(widget.roleId)
            ? 'Enter a symbol. Suggestions can target Practice or a live '
                'portfolio. Confirm in chat before any order.'
            : 'Enter a symbol. Omniscope will add a market snapshot when available.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _submit,
          child: const Text('Run'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Symbol', style: theme.textTheme.small),
            const SizedBox(height: 6),
            ShadInput(
              controller: _symbol,
              placeholder: const Text('e.g. BTC_USD'),
              onSubmitted: (_) => _submit(),
            ),
            if (_isTrading) ...[
              const SizedBox(height: 14),
              Text('Side (optional)', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadSelect<String>(
                minWidth: double.infinity,
                initialValue: _side,
                options: const [
                  ShadOption(value: 'buy', child: Text('Buy')),
                  ShadOption(value: 'sell', child: Text('Sell')),
                ],
                selectedOptionBuilder: (context, value) =>
                    Text(value == 'sell' ? 'Sell' : 'Buy'),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _side = value);
                },
              ),
              const SizedBox(height: 14),
              Text('Quantity (optional)', style: theme.textTheme.small),
              const SizedBox(height: 6),
              ShadInput(
                controller: _qty,
                placeholder: const Text('e.g. 0.01'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
