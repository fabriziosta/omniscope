import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'agent_app_settings.dart';
import 'chat_models.dart';
import 'schedule_chat_binding.dart';

/// Persists agent-agnostic chat threads on device.
class AgentChatRepository extends ChangeNotifier {
  AgentChatRepository({this.store, this.appSettings});

  /// Soft cap so the config file stays small on all platforms.
  static const maxMessagesPerThread = 100;

  /// Hard product cap on how many chats may have Autopilot on at once.
  static const maxAutopilotEnabledChats = 5;

  UserConfigStore? store;

  /// Optional so deleting the schedule home chat can stop Schedule.
  AgentAppSettings? appSettings;
  AgentChatsState _state = AgentChatsState.empty;
  bool _ready = false;

  AgentChatsState get state => _state;
  bool get isReady => _ready;

  List<AgentChatThread> get threads => _state.sortedByUpdated;

  AgentChatThread threadFor(String chatId) => _state.threadFor(chatId);

  /// How many threads currently have Autopilot enabled.
  int get autopilotEnabledCount =>
      _state.threads.where((t) => t.autopilotEnabled).length;

  /// True when another chat may turn Autopilot on (under [maxAutopilotEnabledChats]).
  bool get canEnableAutopilot =>
      autopilotEnabledCount < maxAutopilotEnabledChats;

  /// Null when [chatId] may enable Autopilot; otherwise a short UI message.
  String? autopilotEnableBlockReason(String chatId) {
    final existing = _state.byId(chatId);
    if (existing == null) return null;
    if (existing.autopilotEnabled) return null;
    if (canEnableAutopilot) return null;
    return 'Autopilot limit: at most $maxAutopilotEnabledChats chats. '
        'Turn one off first.';
  }

  /// Prefer [chatId], else the thread that contains [sourceMessageId].
  AgentChatThread? findThread({
    String? chatId,
    String? sourceMessageId,
  }) {
    final id = chatId?.trim();
    if (id != null && id.isNotEmpty) {
      final exact = _state.byId(id);
      if (exact != null) return exact;
    }
    final messageId = sourceMessageId?.trim();
    if (messageId == null || messageId.isEmpty) return null;
    for (final thread in _state.threads) {
      for (final message in thread.messages) {
        if (message.id == messageId) return thread;
      }
    }
    return null;
  }

  /// Whether [chatId] has a message whose [proposalId] is pending actionable.
  bool threadHasPendingProposal(
    String chatId, {
    required bool Function(String proposalId) isPending,
  }) {
    final thread = _state.byId(chatId);
    if (thread == null) return false;
    for (final message in thread.messages) {
      final pid = message.proposalId?.trim();
      if (pid == null || pid.isEmpty) continue;
      if (isPending(pid)) return true;
    }
    return false;
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.agentChats);
    if (slice is! Map) {
      _state = AgentChatsState.empty;
    } else {
      try {
        _state = AgentChatsState.fromJson(Map<String, dynamic>.from(slice));
      } catch (_) {
        _state = AgentChatsState.empty;
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.agentChats, _state.toJson());
  }

  /// Creates an empty chat and returns it.
  Future<AgentChatThread> createChat({
    String? title,
    bool autopilotEnabled = false,
  }) async {
    final thread = AgentChatThread.empty(
      chatId: AgentChatThread.newChatId(),
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'New chat',
      autopilotEnabled: autopilotEnabled,
    ).copyWith(updatedAt: DateTime.now().toUtc());
    _state = _state.withThread(thread);
    await _persist();
    notifyListeners();
    return thread;
  }

  /// One-shot: if legacy global Autopilot was ON, enable it on every existing
  /// thread and clear the global flag so it does not re-apply.
  Future<void> migrateGlobalAutopilotIfNeeded(AgentAppSettings app) async {
    if (!app.autopilotEnabled) return;
    final migrated = <AgentChatThread>[];
    var anyThreadUpdated = false;
    for (final thread in _state.threads) {
      if (thread.autopilotEnabled) {
        migrated.add(thread);
      } else {
        migrated.add(thread.copyWith(autopilotEnabled: true));
        anyThreadUpdated = true;
      }
    }
    if (anyThreadUpdated) {
      _state = AgentChatsState(threads: migrated);
      await _persist();
      notifyListeners();
    }
    await app.setAutopilot(enabled: false);
  }

  Future<AgentChatThread> renameChat(String chatId, String title) async {
    final existing = _state.threadFor(chatId);
    final next = existing.copyWith(
      title: title.trim().isEmpty ? existing.title : title.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  /// Pins or unpins a chat. Does not bump [AgentChatThread.updatedAt].
  Future<AgentChatThread> setPinned(String chatId, {required bool pinned}) async {
    final existing = _state.byId(chatId);
    if (existing == null) {
      return _state.threadFor(chatId);
    }
    if (existing.pinned == pinned) return existing;
    final next = existing.copyWith(pinned: pinned);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  Future<AgentChatThread> togglePinned(String chatId) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    return setPinned(chatId, pinned: !existing.pinned);
  }

  /// Enables or disables Autopilot for one chat. Does not bump [updatedAt].
  ///
  /// Enabling is refused when [autopilotEnabledCount] is already at
  /// [maxAutopilotEnabledChats] (returns the unchanged thread). A successful
  /// enable also sets [AgentChatThread.pinned] so the chat stays at the top of
  /// the list; disable leaves [pinned] unchanged.
  Future<AgentChatThread> setAutopilotEnabled(
    String chatId, {
    required bool enabled,
  }) async {
    final existing = _state.byId(chatId);
    if (existing == null) {
      return _state.threadFor(chatId);
    }
    if (existing.autopilotEnabled == enabled) return existing;
    if (enabled && !canEnableAutopilot) return existing;
    final next = enabled
        ? existing.copyWith(autopilotEnabled: true, pinned: true)
        : existing.copyWith(autopilotEnabled: false);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  Future<AgentChatThread> toggleAutopilotEnabled(String chatId) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    return setAutopilotEnabled(chatId, enabled: !existing.autopilotEnabled);
  }

  /// Enables or disables shared memory for one chat. Does not bump [updatedAt].
  Future<AgentChatThread> setMemoryEnabled(
    String chatId, {
    required bool enabled,
  }) async {
    final existing = _state.byId(chatId);
    if (existing == null) {
      return _state.threadFor(chatId);
    }
    if (existing.memoryEnabled == enabled) return existing;
    final next = existing.copyWith(memoryEnabled: enabled);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  Future<AgentChatThread> toggleMemoryEnabled(String chatId) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    return setMemoryEnabled(chatId, enabled: !existing.memoryEnabled);
  }

  Future<AgentChatThread> append({
    required String chatId,
    required AgentChatMessage message,
    String? titleIfEmpty,
  }) async {
    final existing = _state.threadFor(chatId);
    var messages = List<AgentChatMessage>.from(existing.messages)..add(message);
    if (messages.length > maxMessagesPerThread) {
      messages = messages.sublist(messages.length - maxMessagesPerThread);
    }
    var title = existing.title;
    if (existing.isEmpty &&
        title == 'New chat' &&
        titleIfEmpty != null &&
        titleIfEmpty.trim().isNotEmpty) {
      title = _titleFromContent(titleIfEmpty);
    } else if (existing.isEmpty &&
        title == 'New chat' &&
        message.role == AgentChatRole.user) {
      title = _titleFromContent(message.content);
    }
    final thread = AgentChatThread(
      chatId: chatId,
      title: title,
      messages: messages,
      updatedAt: DateTime.now().toUtc(),
      pinned: existing.pinned,
      autopilotEnabled: existing.autopilotEnabled,
      memoryEnabled: existing.memoryEnabled,
      legacyRoleId: existing.legacyRoleId,
    );
    _state = _state.withThread(thread);
    await _persist();
    notifyListeners();
    return thread;
  }

  static String _titleFromContent(String content) {
    final t = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'New chat';
    return t.length <= 48 ? t : '${t.substring(0, 45)}…';
  }

  Future<void> clearThread(String chatId) async {
    final existing = _state.byId(chatId);
    if (existing == null) return;
    _state = _state.withThread(
      existing.copyWith(
        messages: const [],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> deleteChat(String chatId) async {
    _state = _state.withoutThread(chatId);
    await _persist();
    notifyListeners();
    final app = appSettings;
    if (app != null) {
      await ScheduleChatBinding.stopIfLinkedChatDeleted(
        app: app,
        chatId: chatId,
      );
    }
  }

  /// Clears every persisted agent chat thread on this device.
  Future<void> clearAllThreads() async {
    _state = AgentChatsState.empty;
    await _persist();
    notifyListeners();
    final app = appSettings;
    if (app != null) {
      await ScheduleChatBinding.stopAfterClearAllChats(app);
    }
  }
}
