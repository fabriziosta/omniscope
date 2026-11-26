import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/invest_interest_proposal_actions.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/overflow_actions_menu.dart';
import 'chat_agent_settings_editor.dart';
import 'chat_mandate_editor.dart';

/// Shared Pin / Autopilot / Memory / Rename / Delete actions for a chat.
///
/// Used by the Agents list overflow and the chat title ⋯ menu so both stay
/// in sync.
class AgentChatOptions {
  AgentChatOptions._();

  static Future<void> copyChat(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    final text = thread.plainTextExchange.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Copied',
      description: 'Full chat copied to clipboard.',
    );
  }

  static Future<void> togglePin(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    await context.read<AgentChatRepository>().togglePinned(thread.chatId);
  }

  static Future<void> toggleAutopilot(
    BuildContext context,
    AgentChatThread thread,
  ) async {
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
    if (next && context.mounted) {
      final actions = InvestInterestProposalActions(
        proposals: context.read<InvestInterestProposalRepository>(),
        activity: context.read<AgentActivityRepository>(),
        favorites: context.read<FavoritesRepository>(),
        chats: chats,
      );
      appliedIi =
          await actions.applyPendingAutopilotAddsForChat(thread.chatId);
    }
    if (!context.mounted) return;
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

  static Future<void> toggleMemory(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    final next = !thread.memoryEnabled;
    await context.read<AgentChatRepository>().setMemoryEnabled(
          thread.chatId,
          enabled: next,
        );
    if (!context.mounted) return;
    showAppToast(
      context,
      description: next
          ? 'Memory on for this chat'
          : 'Memory off for this chat',
    );
  }

  static Future<void> editMandate(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    await showChatMandateEditor(context, thread);
  }

  static Future<void> editAgentSettings(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    await showChatAgentSettingsEditor(context, thread);
  }

  static Future<void> rename(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    final controller = TextEditingController(text: thread.title);
    final next = await showAppDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Rename chat'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ShadInput(
            controller: controller,
            autofocus: true,
            placeholder: const Text('Chat name'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
      ),
    );
    final trimmed = next?.trim();
    controller.dispose();
    if (trimmed == null || trimmed.isEmpty || !context.mounted) return;
    if (trimmed == thread.title) return;
    await context.read<AgentChatRepository>().renameChat(thread.chatId, trimmed);
  }

  /// Deletes [thread] after optional confirm. Returns true when deleted.
  static Future<bool> delete(
    BuildContext context,
    AgentChatThread thread,
  ) async {
    final chats = context.read<AgentChatRepository>();
    final id = thread.chatId;
    final wasScheduleChat =
        context.read<AgentAppSettings>().scheduleChatId == id;
    if (thread.pinned) {
      final ok = await confirmDestructiveAction(
        context,
        title: 'Delete pinned chat?',
        description: wasScheduleChat
            ? '“${thread.title}” is pinned and linked to Schedule. '
                'Deleting it removes the conversation and stops Schedule. '
                'This cannot be undone.'
            : '“${thread.title}” is pinned. Deleting it removes the '
                'conversation from this device. This cannot be undone.',
        confirmLabel: 'Delete',
      );
      if (!ok || !context.mounted) return false;
    }
    await chats.deleteChat(id);
    if (!context.mounted) return true;
    if (wasScheduleChat) {
      showAppToast(
        context,
        description: 'Schedule stopped (chat deleted)',
      );
    }
    return true;
  }
}

/// ⋯ menu with the shared chat options (list row and chat title).
class AgentChatOptionsMenu extends StatelessWidget {
  const AgentChatOptionsMenu({
    super.key,
    required this.thread,
    this.tooltip = 'Chat settings',
    this.onDeleted,
  });

  final AgentChatThread thread;
  final String tooltip;

  /// Called after a successful delete (e.g. clear Agents selection).
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return OverflowActionsMenu(
      tooltip: tooltip,
      actions: [
        if (thread.messages.isNotEmpty)
          OverflowAction(
            label: 'Copy chat',
            icon: LucideIcons.copy,
            onTap: () {
              AgentChatOptions.copyChat(context, thread);
            },
          ),
        OverflowAction(
          label: thread.pinned ? 'Unpin' : 'Pin',
          icon: thread.pinned ? LucideIcons.pinOff : LucideIcons.pin,
          active: thread.pinned,
          onTap: () {
            AgentChatOptions.togglePin(context, thread);
          },
        ),
        OverflowAction(
          label: thread.autopilotEnabled ? 'Autopilot off' : 'Autopilot on',
          icon: LucideIcons.zap,
          active: thread.autopilotEnabled,
          onTap: () {
            AgentChatOptions.toggleAutopilot(context, thread);
          },
        ),
        OverflowAction(
          label: thread.memoryEnabled ? 'Memory off' : 'Memory on',
          icon: LucideIcons.brain,
          active: thread.memoryEnabled,
          onTap: () {
            AgentChatOptions.toggleMemory(context, thread);
          },
        ),
        OverflowAction(
          label: 'Agent settings…',
          icon: LucideIcons.slidersHorizontal,
          onTap: () {
            AgentChatOptions.editAgentSettings(context, thread);
          },
        ),
        OverflowAction(
          label: 'Mandate…',
          icon: LucideIcons.crosshair,
          onTap: () {
            AgentChatOptions.editMandate(context, thread);
          },
        ),
        OverflowAction(
          label: 'Rename',
          icon: LucideIcons.pencil,
          onTap: () {
            AgentChatOptions.rename(context, thread);
          },
        ),
        OverflowAction(
          label: 'Delete',
          icon: LucideIcons.trash2,
          onTap: () async {
            final deleted = await AgentChatOptions.delete(context, thread);
            if (deleted) onDeleted?.call();
          },
        ),
      ],
    );
  }
}
