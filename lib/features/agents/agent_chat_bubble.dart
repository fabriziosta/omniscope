import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/trade_proposal.dart';
import '../../widgets/agent_markdown_body.dart';
import '../../widgets/app_text.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import 'agent_proposal_cards.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
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
                child: TradeProposalCard(
                  proposal: proposal!,
                  onConfirm: onConfirm,
                  onDismiss: onDismiss,
                  busy: busy,
                ),
              ),
            if (investInterestProposal != null)
              SelectionContainer.disabled(
                child: InvestInterestProposalCard(
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
