import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/tab_page_header.dart';
import 'agent_chat_screen.dart';

/// Agents tab: chat history sidebar + embedded orchestrator chat.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  /// Wide layout selection when threads exist.
  String? _selectedChatId;

  /// Narrow: null = history list only.
  String? _narrowSelected;

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

  bool get _wide =>
      MediaQuery.sizeOf(context).width >= AgentsScreen.wideBreakpoint;

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
    _launchAutoRun = pending.autoRun ||
        pending.starterRoleId != null ||
        (pending.symbol != null && pending.symbol!.isNotEmpty);
    _launchSide = pending.initialSide;
    _launchQuantity = pending.initialQuantity;
    _launchStarterRoleId = pending.starterRoleId;
    _launchGeneration++;
  }

  void _selectChat(
    String chatId, {
    required bool wide,
    bool fromLaunch = false,
  }) {
    setState(() {
      if (!fromLaunch) {
        _clearLaunchParams();
      }
      _selectedChatId = chatId;
      // Always set narrow selection for launches so the chat is visible even
      // if MediaQuery width is reported as wide during the shell callback.
      if (!wide || fromLaunch) {
        _narrowSelected = chatId;
      }
    });
  }

  void _backToNavList() {
    setState(() {
      _narrowSelected = null;
      _clearLaunchParams();
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
      _selectChat(chatId, wide: _wide, fromLaunch: true);
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

  Future<void> _newChat() async {
    if (!await _ensureLlmReady()) return;
    if (!mounted) return;
    final chats = context.read<AgentChatRepository>();
    final thread = await chats.createChat();
    if (!mounted) return;
    setState(() {
      _clearLaunchParams();
      _selectedChatId = thread.chatId;
      // Always set narrow selection so the new chat opens even if MediaQuery
      // width is reported as wide during this callback (matches launch path).
      _narrowSelected = thread.chatId;
    });
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
    await chats.deleteChat(id);
    if (!mounted) return;
    setState(() {
      if (_selectedChatId == id) {
        final next = chats.threads.isEmpty ? null : chats.threads.first.chatId;
        _selectedChatId = next;
        _clearLaunchParams();
      }
      if (_narrowSelected == id) {
        _narrowSelected = null;
      }
    });
  }

  Future<void> _togglePin(AgentChatThread thread) async {
    await context.read<AgentChatRepository>().togglePinned(thread.chatId);
  }

  Widget _buildSidebar({
    required List<AgentChatThread> threads,
    required bool ready,
    required String? highlighted,
    required bool wide,
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
              onPressed: () => _newChat(),
              child: const Text('New chat'),
            ),
          ),
        ),
        Expanded(
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
                      onOpen: () => _selectChat(thread.chatId, wide: wide),
                      onTogglePin: () => _togglePin(thread),
                      onRename: () => _renameChat(thread),
                      onDelete: () => _deleteChat(thread),
                    );
                  },
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

    // Wide: keep a concrete selection when threads exist.
    final selectedId = () {
      if (_selectedChatId != null &&
          threads.any((t) => t.chatId == _selectedChatId)) {
        return _selectedChatId!;
      }
      return threads.isEmpty ? null : threads.first.chatId;
    }();

    final narrowId = _narrowSelected != null &&
            threads.any((t) => t.chatId == _narrowSelected)
        ? _narrowSelected
        : null;

    return InTabBackEffect(
      onBack: narrowId != null ? _backToNavList : null,
      child: ColoredBox(
        color: theme.colorScheme.background,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrowId == null)
                const TabPageHeader(
                  title: 'Agents',
                  subtitle:
                      'Chats use your LLM keys. Specialists run in the background.',
                ),
              Expanded(
                child: selectedId == null
                    ? _buildSidebar(
                        threads: threads,
                        ready: ready,
                        highlighted: null,
                        wide: _wide,
                      )
                    : MasterDetailShell<String>(
                        selected: selectedId,
                        narrowSelected: narrowId,
                        onNarrowBack: _backToNavList,
                        sidebarBuilder: (context, highlighted, {required wide}) {
                          return _buildSidebar(
                            threads: threads,
                            ready: ready,
                            highlighted: highlighted,
                            wide: wide,
                          );
                        },
                        contentBuilder:
                            (context, chatId, {required showBack, onBack}) {
                          return KeyedSubtree(
                            key: ValueKey('$chatId-$_launchGeneration'),
                            child: AgentChatScreen(
                              chatId: chatId,
                              showBack: showBack,
                              onBack: onBack,
                              backLabel: 'Agents',
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
            ],
          ),
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
    required this.onRename,
    required this.onDelete,
  });

  final AgentChatThread thread;
  final bool selected;
  final VoidCallback onOpen;
  final Future<void> Function() onTogglePin;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final preview = thread.messages.isEmpty
        ? 'Empty chat'
        : thread.messages.last.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short =
        preview.length <= 80 ? preview : '${preview.substring(0, 77)}…';
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;
    final pinColor = thread.pinned
        ? (selected
            ? theme.colorScheme.secondaryForeground
            : theme.colorScheme.primary)
        : muted;
    final updatedLabel = thread.updatedAt.millisecondsSinceEpoch == 0
        ? null
        : formatRelativeTime(thread.updatedAt);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
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
                      Text(
                        thread.title,
                        style: theme.textTheme.large.copyWith(color: foreground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (updatedLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          updatedLabel,
                          style: theme.textTheme.muted.copyWith(
                            color: muted,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        short,
                        style: theme.textTheme.muted.copyWith(color: muted),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                AppTooltip(
                  message: thread.pinned ? 'Unpin' : 'Pin',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      await onTogglePin();
                    },
                    child: Icon(
                      thread.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                      size: 14,
                      color: pinColor,
                    ),
                  ),
                ),
                AppTooltip(
                  message: 'Rename',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      await onRename();
                    },
                    child: Icon(
                      LucideIcons.pencil,
                      size: 14,
                      color: muted,
                    ),
                  ),
                ),
                AppTooltip(
                  message: 'Delete',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      await onDelete();
                    },
                    child: Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
