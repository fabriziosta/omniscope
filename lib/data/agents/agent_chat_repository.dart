import 'package:flutter/foundation.dart';

import '../settings/mandate_settings.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_migrations.dart';
import '../settings/user_config_store.dart';
import 'agent_app_settings.dart';
import 'chat_agent_settings.dart';
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
  bool _writeLegacyRoleIdKeys = true;

  /// Chat ids whose persisted JSON lacked a `mandate` key (need one-shot seed).
  final Set<String> _threadsMissingMandate = {};

  /// Chat ids whose persisted JSON lacked `agentSettings` (need one-shot seed).
  final Set<String> _threadsMissingAgentSettings = {};

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
    _threadsMissingMandate.clear();
    _threadsMissingAgentSettings.clear();
    final slice = this.store?.getSlice(UserConfigKeys.agentChats);
    if (slice is! Map) {
      _state = AgentChatsState.empty;
    } else {
      try {
        final map = Map<String, dynamic>.from(slice);
        final rawThreads = map['threads'] as List? ?? const [];
        for (final item in rawThreads) {
          if (item is! Map) continue;
          final threadMap = Map<String, dynamic>.from(item);
          final id = _threadIdFromRaw(threadMap);
          if (id == null) continue;
          if (!threadMap.containsKey('mandate')) {
            _threadsMissingMandate.add(id);
          }
          if (!threadMap.containsKey('agentSettings')) {
            _threadsMissingAgentSettings.add(id);
          }
        }
        _state = AgentChatsState.fromJson(map);
      } catch (_) {
        _state = AgentChatsState.empty;
        _threadsMissingMandate.clear();
        _threadsMissingAgentSettings.clear();
      }
    }
    final cfg = store;
    _writeLegacyRoleIdKeys = cfg != null &&
        UserConfigMigrations.readVersion(cfg) < UserConfigKeys.currentVersion;
    _ready = true;
    notifyListeners();
  }

  /// When false, persisted threads omit legacy `roleId` / `legacyRoleId` keys.
  void setWriteLegacyRoleIdKeys(bool value) {
    _writeLegacyRoleIdKeys = value;
  }

  /// Clears in-memory legacy role ids and re-persists without legacy JSON keys.
  Future<void> stripLegacyRoleIdKeys() async {
    var changed = false;
    final migrated = <AgentChatThread>[];
    for (final thread in _state.threads) {
      if (thread.legacyRoleId != null) {
        changed = true;
        migrated.add(thread.copyWith(clearLegacyRoleId: true));
      } else {
        migrated.add(thread);
      }
    }
    if (!changed) return;
    _state = AgentChatsState(threads: migrated);
    await _persist();
    notifyListeners();
  }

  static String? _threadIdFromRaw(Map<String, dynamic> threadMap) {
    final id = (threadMap['chatId'] as String?)?.trim();
    if (id != null && id.isNotEmpty) return id;
    final legacyRoleId = threadMap['legacyRoleId'] as String? ??
        threadMap['roleId'] as String?;
    if (legacyRoleId != null && legacyRoleId.isNotEmpty) {
      return 'legacy_$legacyRoleId';
    }
    return null;
  }

  Future<void> _persist() async {
    await store?.setSlice(
      UserConfigKeys.agentChats,
      _state.toJson(writeLegacyRoleIdKeys: _writeLegacyRoleIdKeys),
    );
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

  /// Most recently updated empty chat whose title matches [title], if any.
  ///
  /// Used by in-app launch CTAs so repeated taps reuse one draft chat instead
  /// of spawning duplicates.
  AgentChatThread? emptyChatWithTitle(String title) {
    final want = title.trim();
    if (want.isEmpty) return null;
    for (final thread in threads) {
      if (thread.messages.isEmpty && thread.title.trim() == want) {
        return thread;
      }
    }
    return null;
  }

  /// Bumps [AgentChatThread.updatedAt] so a reused draft floats in the list.
  Future<AgentChatThread> touchChat(String chatId) async {
    final existing = _state.byId(chatId);
    if (existing == null) return threadFor(chatId);
    final next = existing.copyWith(updatedAt: DateTime.now().toUtc());
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
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

  /// One-shot: seed threads that lacked a per-chat `mandate` from the legacy
  /// top-level `mandate` config slice (or [ChatMandate.defaults]), then clear
  /// the global slice so it does not re-apply.
  Future<void> migrateGlobalMandateIfNeeded() async {
    final legacySlice = store?.getSlice(UserConfigKeys.mandate);
    final seed = ChatMandate.fromJson(legacySlice);
    final hasLegacySlice = legacySlice is Map;
    final needSeed = _threadsMissingMandate.isNotEmpty;
    if (!needSeed && !hasLegacySlice) return;

    if (needSeed) {
      final migrated = <AgentChatThread>[
        for (final thread in _state.threads)
          if (_threadsMissingMandate.contains(thread.chatId))
            thread.copyWith(mandate: seed)
          else
            thread,
      ];
      _state = AgentChatsState(threads: migrated);
      _threadsMissingMandate.clear();
      await _persist();
      notifyListeners();
    }

    if (hasLegacySlice) {
      await store?.setSlice(UserConfigKeys.mandate, <String, dynamic>{});
    }
  }

  /// Replaces this chat's Mandate. Does not bump [updatedAt].
  Future<AgentChatThread> setMandate(String chatId, ChatMandate mandate) async {
    final existing = _state.byId(chatId);
    if (existing == null) {
      return _state.threadFor(chatId);
    }
    if (existing.mandate == mandate) return existing;
    final next = existing.copyWith(mandate: mandate);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  /// One-shot: seed threads that lacked `agentSettings` from global
  /// [AgentAppSettings] mood / roles / portfolio, then clear those fields.
  Future<void> migrateGlobalAgentSettingsIfNeeded(AgentAppSettings app) async {
    final needSeed = _threadsMissingAgentSettings.isNotEmpty;
    final hasLegacyChatFields = app.hasLegacyChatScopedFields;
    if (!needSeed && !hasLegacyChatFields) return;

    if (needSeed) {
      final seed = ChatAgentSettings.fromAppSettings(app);
      final migrated = <AgentChatThread>[
        for (final thread in _state.threads)
          if (_threadsMissingAgentSettings.contains(thread.chatId))
            thread.copyWith(agentSettings: seed)
          else
            thread,
      ];
      _state = AgentChatsState(threads: migrated);
      _threadsMissingAgentSettings.clear();
      await _persist();
      notifyListeners();
    }

    if (hasLegacyChatFields) {
      await app.clearChatScopedFields();
    }
  }

  /// Replaces this chat's agent prefs. Does not bump [updatedAt].
  Future<AgentChatThread> setAgentSettings(
    String chatId,
    ChatAgentSettings settings,
  ) async {
    final existing = _state.byId(chatId);
    if (existing == null) {
      return _state.threadFor(chatId);
    }
    if (existing.agentSettings == settings) return existing;
    final next = existing.copyWith(agentSettings: settings);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
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

  /// Replaces this chat's focus symbols. Does not bump [updatedAt].
  Future<AgentChatThread> setFocusSymbols(
    String chatId,
    List<String> symbols,
  ) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    final nextSymbols = AgentChatThread.normalizeFocusSymbols(symbols);
    if (_sameFocusSymbols(existing.focusSymbols, nextSymbols)) {
      return existing;
    }
    final next = existing.copyWith(focusSymbols: nextSymbols);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  /// Appends symbols to this chat's focus list (deduped, capped). No [updatedAt].
  Future<AgentChatThread> pinFocusSymbols(
    String chatId,
    Iterable<String> symbols,
  ) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    final nextSymbols = AgentChatThread.mergeFocusSymbols(
      existing.focusSymbols,
      symbols,
    );
    if (_sameFocusSymbols(existing.focusSymbols, nextSymbols)) {
      return existing;
    }
    final next = existing.copyWith(focusSymbols: nextSymbols);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  /// Removes symbols from this chat's focus list. Does not bump [updatedAt].
  Future<AgentChatThread> unpinFocusSymbols(
    String chatId,
    Iterable<String> symbols,
  ) async {
    final existing = _state.byId(chatId);
    if (existing == null) return _state.threadFor(chatId);
    final nextSymbols = AgentChatThread.withoutFocusSymbols(
      existing.focusSymbols,
      symbols,
    );
    if (_sameFocusSymbols(existing.focusSymbols, nextSymbols)) {
      return existing;
    }
    final next = existing.copyWith(focusSymbols: nextSymbols);
    _state = _state.withThread(next);
    await _persist();
    notifyListeners();
    return next;
  }

  static bool _sameFocusSymbols(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
      focusSymbols: existing.focusSymbols,
      mandate: existing.mandate,
      agentSettings: existing.agentSettings,
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
