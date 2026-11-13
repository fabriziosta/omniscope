import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_chat_client.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'agent_chat_controller.dart';

class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({
    super.key,
    required this.role,
    this.initialSymbol,
    this.autoRun = false,
    this.initialSide,
    this.initialQuantity,
  });

  final AgentRoleDefinition role;

  /// Optional symbol for deep-link / Investigate launches.
  final String? initialSymbol;

  /// When true and [initialSymbol] is set, send a Run on first open.
  final bool autoRun;

  final String? initialSide;
  final double? initialQuantity;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AgentChatController(
        role: role,
        agents: context.read<AgentsRepository>(),
        chats: context.read<AgentChatRepository>(),
        marketData: context.read<MarketDataClient>(),
        llm: context.read<LlmChatClient>(),
        tradeExecutor: context.read<TradeExecutor>(),
        proposals: context.read<TradeProposalRepository>(),
        activity: context.read<AgentActivityRepository>(),
        cryptoRegistry: context.read<CryptoExchangeRegistry>(),
        dataSources: context.read<DataSourceSettings>(),
      ),
      child: _AgentChatView(
        role: role,
        initialSymbol: initialSymbol,
        autoRun: autoRun,
        initialSide: initialSide,
        initialQuantity: initialQuantity,
      ),
    );
  }
}

class _AgentChatView extends StatefulWidget {
  const _AgentChatView({
    required this.role,
    this.initialSymbol,
    this.autoRun = false,
    this.initialSide,
    this.initialQuantity,
  });

  final AgentRoleDefinition role;
  final String? initialSymbol;
  final bool autoRun;
  final String? initialSide;
  final double? initialQuantity;

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
    final symbol = widget.initialSymbol?.trim();
    if (symbol == null || symbol.isEmpty) return;
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    _autoRunStarted = true;
    final result = await controller.sendRun(
      symbol: symbol,
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
        title: 'Connect an exchange',
        description:
            'Trade suggestions need a live exchange. Open Settings → '
            'Data sources to add API credentials.',
        destructive: true,
      );
    }
  }

  Future<void> _sendFreeform() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    _composer.clear();
    final result = await controller.sendFreeform(text);
    await _handleSendResult(result);
  }

  Future<void> _openRunSheet() async {
    final controller = context.read<AgentChatController>();
    if (controller.sending) return;
    if (AgentRolePrompts.supportsTradeProposals(widget.role.id) &&
        !controller.hasTradableExchange) {
      await _handleSendResult(const AgentChatSendBlockedNoExchange());
      return;
    }
    final result = await showShadDialog<_RunSheetResult>(
      context: context,
      builder: (context) => _RunAgentDialog(
        roleId: widget.role.id,
        initialSymbol: widget.initialSymbol,
      ),
    );
    if (result == null || !mounted) return;
    final sendResult = await controller.sendRun(
      symbol: result.symbol,
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
          'Removes the saved conversation for this agent on this device. '
          'This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (ok && mounted) {
      await context.read<AgentChatController>().clearThread();
    }
  }

  Future<void> _confirmProposal(TradeProposal proposal) async {
    final controller = context.read<AgentChatController>();
    final err = await controller.confirmProposal(proposal.id);
    if (!mounted) return;
    if (err != null) {
      showAppToast(context, description: err, destructive: true);
    } else {
      showAppToast(
        context,
        description:
            'Order submitted to ${proposal.exchangeId} for ${proposal.symbol}',
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

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final thread =
        context.watch<AgentChatRepository>().threadFor(widget.role.id);
    final connected =
        context.watch<AgentsRepository>().forRoleId(widget.role.id).connected;
    final controller = context.watch<AgentChatController>();
    final proposals = context.watch<TradeProposalRepository>();
    // Rebuild when credentials / toggles change so the exchange gate updates.
    context.watch<EnvSecretsRepository>();
    context.watch<DataSourceSettings>();
    final tradeExecutor = context.read<TradeExecutor>();
    final sending = controller.sending;
    final wantsTrade = AgentRolePrompts.supportsTradeProposals(widget.role.id);
    final canTrade = tradeExecutor.canTrade;

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubscreenAppBar(
              title: widget.role.title,
              trailing: ShadButton.outline(
                size: ShadButtonSize.sm,
                enabled: !thread.isEmpty && !sending,
                onPressed: _confirmClear,
                child: const Text('Clear'),
              ),
            ),
            if (wantsTrade && !canTrade)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                          'Configure a live exchange to get trade suggestions. '
                          'Practice (paper) portfolio is separate and never '
                          'used for AI orders.',
                          style: theme.textTheme.small.copyWith(
                            color: theme.colorScheme.secondaryForeground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 44,
                          child: ShadButton(
                            onPressed: () {
                              context.read<ShellNavigationController>().goToSettings(
                                    sectionId: 'dataSources',
                                  );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Open Data sources'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  connected
                      ? (wantsTrade
                          ? 'Suggestions target a connected exchange. '
                              'Confirm before any live order.'
                          : 'Chat is saved on this device. Use Run for a symbol.')
                      : 'This agent is disconnected.',
                  style: theme.textTheme.muted,
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: thread.messages.isEmpty
                  ? AppEmptyView(
                      wantsTrade && !canTrade
                          ? 'Connect an exchange under Settings → Data sources, '
                              'then run a symbol for live suggestions.'
                          : 'Ask a question or run a symbol investigation. '
                              'Messages stay on this device.',
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: thread.messages.length + (sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (sending && index == thread.messages.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AppProgress(compact: true),
                            ),
                          );
                        }
                        final message = thread.messages[index];
                        final proposalId = message.proposalId;
                        final proposal = proposalId == null
                            ? null
                            : proposals.byId(proposalId);
                        return _ChatBubble(
                          message: message,
                          proposal: proposal,
                          busy: controller.actingOnProposal,
                          onConfirm: proposal != null &&
                                  proposal.status == TradeProposalStatus.pending &&
                                  proposal.side != TradeProposalSide.hold
                              ? () => _confirmProposal(proposal)
                              : null,
                          onDismiss: proposal != null &&
                                  proposal.status == TradeProposalStatus.pending
                              ? () => _dismissProposal(proposal)
                              : null,
                        );
                      },
                    ),
            ),
            if (connected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.secondary(
                    size: ShadButtonSize.sm,
                    enabled: !sending,
                    onPressed: _openRunSheet,
                    child: Text(AgentRolePrompts.runChipLabel(widget.role.id)),
                  ),
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
                        if (!sending && connected) _sendFreeform();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ShadButton(
                      enabled: !sending && connected,
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
    this.onConfirm,
    this.onDismiss,
    this.busy = false,
  });

  final AgentChatMessage message;
  final TradeProposal? proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;
  final bool busy;

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
              margin: const EdgeInsets.symmetric(vertical: 6),
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
                  Text(
                    message.content,
                    style: theme.textTheme.p.copyWith(color: fg),
                  ),
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
          ],
        ),
      ),
    );
  }
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
            'Exchange: ${proposal.exchangeId} · ${proposal.status.label}'
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
      widget.roleId == 'intradayTrading' || widget.roleId == 'hedgeFundDesk';

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
            ? 'Enter a symbol. Suggestions target a connected live exchange '
                '(not paper). Confirm in chat before any order.'
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
