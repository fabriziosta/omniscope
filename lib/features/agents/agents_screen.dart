import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_text.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/autopilot_status_pill.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/overflow_actions_menu.dart';
import '../../widgets/schedule_status_pill.dart';
import 'agent_chat_screen.dart';

/// Agents tab: chat history sidebar + embedded orchestrator chat.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  /// Sentinel [MasterDetailShell] selection when there are no chats yet.
  static const emptySelectionId = '';

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  String? _selectedChatId;

  /// One-shot launch params applied when opening from [goToAgentChat].
  String? _launchSymbol;
  String? _launchExchangeId;
  var _launchAutoRun = false;
  String? _launchSide;
  double? _launchQuantity;
  String? _launchStarterRoleId;
  var _launchGeneration = 0;

  ShellNavigationController? _shellNav;
  var _openingPendingChat = false;

  /// Latest [MasterDetailShell] closeNav from [sidebarBuilder].
  VoidCallback? _closeNav;

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
      _maybeOpenPendingChat();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() {
    _maybeOpenPendingChat();
  }

  void _clearLaunchParams() {
    _launchSymbol = null;
    _launchExchangeId = null;
    _launchAutoRun = false;
    _launchSide = null;
    _launchQuantity = null;
    _launchStarterRoleId = null;
  }

  void _applyLaunchParams(PendingAgentChatOpen pending) {
    _launchSymbol = pending.symbol;
    _launchExchangeId = pending.initialExchangeId;
    _launchAutoRun = pending.autoRun;
    _launchSide = pending.initialSide;
    _launchQuantity = pending.initialQuantity;
    _launchStarterRoleId = pending.starterRoleId;
    _launchGeneration++;
  }

  void _selectChat(String chatId, {bool fromLaunch = false}) {
    setState(() {
      if (!fromLaunch) {
        _clearLaunchParams();
      }
      _selectedChatId = chatId;
    });
  }

  Future<void> _maybeOpenPendingChat() async {
    if (!mounted || _openingPendingChat) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.agentsTabIndex) return;
    final pending = shellNav.takePendingAgentChatOpen();
    if (pending == null) return;

    _openingPendingChat = true;
    try {
      final chats = context.read<AgentChatRepository>();
      final chatId = pending.chatId ??
          (await chats.createChat(
            title: pending.symbol?.isNotEmpty == true ? pending.symbol : null,
          ))
              .chatId;
      if (!mounted) return;
      _applyLaunchParams(pending);
      _selectChat(chatId, fromLaunch: true);
      // Match tapping a chat tile — deep-link should show the composer, not
      // the chat-list drawer.
      _closeNav?.call();
    } finally {
      _openingPendingChat = false;
    }
  }

  Future<bool> _ensureLlmReady() async {
    final secrets = context.read<EnvSecretsRepository>();
    final runtime = context.read<LlmRuntimeSettings>();
    if (LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    )) {
      return true;
    }
    showAppToast(
      context,
      title: 'Add an LLM key',
      description: 'Settings → Connections first, then start a chat.',
      destructive: true,
    );
    context.read<ShellNavigationController>().goToSettings(
          sectionId: 'connections',
        );
    return false;
  }

  Future<void> _newChat({VoidCallback? closeNav}) async {
    if (!await _ensureLlmReady()) return;
    if (!mounted) return;
    final chats = context.read<AgentChatRepository>();
    final thread = await chats.createChat();
    if (!mounted) return;
    setState(() {
      _clearLaunchParams();
      _selectedChatId = thread.chatId;
    });
    closeNav?.call();
  }

  Future<void> _renameChat(AgentChatThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final next = await showShadDialog<String>(
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
            placeholder: const Text('Chat name'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
      ),
    );
    final trimmed = next?.trim();
    controller.dispose();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    if (trimmed == thread.title) return;
    await context.read<AgentChatRepository>().renameChat(thread.chatId, trimmed);
  }

  Future<void> _deleteChat(AgentChatThread thread) async {
    final chats = context.read<AgentChatRepository>();
    final id = thread.chatId;
    final wasScheduleChat =
        context.read<AgentAppSettings>().scheduleChatId == id;
    await chats.deleteChat(id);
    if (!mounted) return;
    if (wasScheduleChat) {
      showAppToast(
        context,
        description: 'Schedule stopped (chat deleted)',
      );
    }
    setState(() {
      if (_selectedChatId == id) {
        final next = chats.threads.isEmpty ? null : chats.threads.first.chatId;
        _selectedChatId = next;
        _clearLaunchParams();
      }
    });
  }

  Future<void> _togglePin(AgentChatThread thread) async {
    await context.read<AgentChatRepository>().togglePinned(thread.chatId);
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
    if (!mounted) return;
    showAppToast(
      context,
      description: next
          ? 'Autopilot on for this chat'
          : 'Autopilot off for this chat',
    );
  }

  Widget _buildSidebar({
    required List<AgentChatThread> threads,
    required bool ready,
    required String? highlighted,
    required VoidCallback closeNav,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ShadButton(
              size: ShadButtonSize.sm,
              onPressed: () => _newChat(closeNav: closeNav),
              child: const Text('New chat'),
            ),
          ),
        ),
        Expanded(
          child: SelectionContainer.disabled(
            child: threads.isEmpty
                ? AppEmptyView(
                    ready
                        ? 'No chats yet — tap New chat to start.'
                        : 'Settings → Connections → add a provider key '
                            'and pick light/heavy models.',
                  )
                : ListView.separated(
                    padding: MasterDetailNavList.listPadding,
                    itemCount: threads.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: MasterDetailNavList.tileGap),
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return _ChatNavTile(
                        thread: thread,
                        selected: highlighted == thread.chatId,
                        onOpen: () {
                          _selectChat(thread.chatId);
                          closeNav();
                        },
                        onTogglePin: () => _togglePin(thread),
                        onToggleAutopilot: () => _toggleAutopilot(thread),
                        onRename: () => _renameChat(thread),
                        onDelete: () => _deleteChat(thread),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final chats = context.watch<AgentChatRepository>();
    final secrets = context.watch<EnvSecretsRepository>();
    final runtime = context.watch<LlmRuntimeSettings>();
    final ready = LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    );
    final threads = chats.threads;

    final selectedId = () {
      if (_selectedChatId != null &&
          threads.any((t) => t.chatId == _selectedChatId)) {
        return _selectedChatId!;
      }
      return threads.isEmpty
          ? AgentsScreen.emptySelectionId
          : threads.first.chatId;
    }();

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: MasterDetailShell<String>(
          selected: selectedId,
          sidebarWidth: 300,
          sidebarBuilder: (context, highlighted, {required closeNav}) {
            _closeNav = closeNav;
            return _buildSidebar(
              threads: threads,
              ready: ready,
              highlighted: highlighted == AgentsScreen.emptySelectionId
                  ? null
                  : highlighted,
              closeNav: closeNav,
            );
          },
          contentBuilder: (context, chatId, {required onOpenMenu}) {
            if (chatId == AgentsScreen.emptySelectionId ||
                !threads.any((t) => t.chatId == chatId)) {
              return MasterDetailContentPane(
                title: 'Agents',
                subtitle:
                    'Chats use your LLM keys. Specialists run in the background.',
                onOpenMenu: onOpenMenu,
                body: AppEmptyView(
                  ready
                      ? 'No chats yet — open the menu and tap New chat.'
                      : 'Settings → Connections → add a provider key '
                          'and pick light/heavy models.',
                ),
              );
            }
            return KeyedSubtree(
              key: ValueKey('$chatId-$_launchGeneration'),
              child: AgentChatScreen(
                chatId: chatId,
                onOpenMenu: onOpenMenu,
                initialSymbol: _launchSymbol,
                initialExchangeId: _launchExchangeId,
                autoRun: _launchAutoRun,
                initialSide: _launchSide,
                initialQuantity: _launchQuantity,
                starterRoleId: _launchStarterRoleId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChatNavTile extends StatelessWidget {
  const _ChatNavTile({
    required this.thread,
    required this.selected,
    required this.onOpen,
    required this.onTogglePin,
    required this.onToggleAutopilot,
    required this.onRename,
    required this.onDelete,
  });

  final AgentChatThread thread;
  final bool selected;
  final VoidCallback onOpen;
  final Future<void> Function() onTogglePin;
  final Future<void> Function() onToggleAutopilot;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;
    final pinColor = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.primary;
    final updatedLabel = thread.updatedAt.millisecondsSinceEpoch == 0
        ? null
        : formatRelativeTime(thread.updatedAt);
    final tooltipMessage = updatedLabel == null
        ? thread.title
        : '${thread.title} · $updatedLabel';

    return AppTooltip(
      message: tooltipMessage,
      wrapDetector: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.border,
              ),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (thread.pinned) ...[
                              Icon(
                                LucideIcons.pin,
                                size: 12,
                                color: pinColor,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: AppEllipsisText(
                                thread.title,
                                style: theme.textTheme.large
                                    .copyWith(color: foreground),
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AutopilotStatusPill(
                              enabled: thread.autopilotEnabled,
                            ),
                            ScheduleStatusPill(chatId: thread.chatId),
                          ],
                        ),
                        if (updatedLabel != null) ...[
                          const SizedBox(height: 2),
                          AppEllipsisText(
                            updatedLabel,
                            style: theme.textTheme.muted.copyWith(
                              color: muted,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                  OverflowActionsMenu(
                    actions: [
                      OverflowAction(
                        label: thread.pinned ? 'Unpin' : 'Pin',
                        icon: thread.pinned
                            ? LucideIcons.pinOff
                            : LucideIcons.pin,
                        active: thread.pinned,
                        onTap: () {
                          onTogglePin();
                        },
                      ),
                      OverflowAction(
                        label: thread.autopilotEnabled
                            ? 'Autopilot off'
                            : 'Autopilot on',
                        icon: LucideIcons.zap,
                        active: thread.autopilotEnabled,
                        onTap: () {
                          onToggleAutopilot();
                        },
                      ),
                      OverflowAction(
                        label: 'Rename',
                        icon: LucideIcons.pencil,
                        onTap: () {
                          onRename();
                        },
                      ),
                      OverflowAction(
                        label: 'Delete',
                        icon: LucideIcons.trash2,
                        onTap: () {
                          onDelete();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
