import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_chat_client.dart';
import '../../data/agents/models.dart';
import '../../data/market/market_data_client.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'agent_chat_controller.dart';

class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({
    super.key,
    required this.role,
  });

  final AgentRoleDefinition role;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AgentChatController(
        role: role,
        agents: context.read<AgentsRepository>(),
        chats: context.read<AgentChatRepository>(),
        marketData: context.read<MarketDataClient>(),
        llm: context.read<LlmChatClient>(),
      ),
      child: _AgentChatView(role: role),
    );
  }
}

class _AgentChatView extends StatefulWidget {
  const _AgentChatView({required this.role});

  final AgentRoleDefinition role;

  @override
  State<_AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends State<_AgentChatView> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

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
    final result = await showShadDialog<_RunSheetResult>(
      context: context,
      builder: (context) => _RunAgentDialog(roleId: widget.role.id),
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
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Clear this chat?'),
        description: const Text(
          'Removes the saved conversation for this agent on this device. '
          'This cannot be undone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AgentChatController>().clearThread();
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
    final sending = controller.sending;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                connected
                    ? 'Chat is saved on this device. Use Run for a symbol.'
                    : 'This agent is disconnected.',
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: thread.messages.isEmpty
                  ? const AppEmptyView(
                      'Ask a question or run a symbol investigation. '
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
                        return _ChatBubble(message: message);
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
  const _ChatBubble({required this.message});

  final AgentChatMessage message;

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
        child: Container(
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
  const _RunAgentDialog({required this.roleId});

  final String roleId;

  @override
  State<_RunAgentDialog> createState() => _RunAgentDialogState();
}

class _RunAgentDialogState extends State<_RunAgentDialog> {
  final _symbol = TextEditingController();
  final _qty = TextEditingController();
  String _side = 'buy';

  bool get _isTrading => widget.roleId == 'intradayTrading';

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
      description: const Text(
        'Enter a symbol. Omniscope will add a market snapshot when available.',
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
              placeholder: const Text('e.g. AAPL'),
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
                placeholder: const Text('e.g. 10'),
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
