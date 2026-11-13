import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'chat_models.dart';

/// Persists one chat thread per agent role on device.
class AgentChatRepository extends ChangeNotifier {
  AgentChatRepository({this.store});

  /// Soft cap so the config file stays small on all platforms.
  static const maxMessagesPerThread = 100;

  UserConfigStore? store;
  AgentChatsState _state = AgentChatsState.empty;
  bool _ready = false;

  AgentChatsState get state => _state;
  bool get isReady => _ready;

  AgentChatThread threadFor(String roleId) => _state.threadFor(roleId);

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

  Future<AgentChatThread> append({
    required String roleId,
    required AgentChatMessage message,
  }) async {
    final existing = _state.threadFor(roleId);
    var messages = List<AgentChatMessage>.from(existing.messages)..add(message);
    if (messages.length > maxMessagesPerThread) {
      messages = messages.sublist(messages.length - maxMessagesPerThread);
    }
    final thread = AgentChatThread(
      roleId: roleId,
      messages: messages,
      updatedAt: DateTime.now().toUtc(),
    );
    _state = _state.withThread(thread);
    await _persist();
    notifyListeners();
    return thread;
  }

  Future<void> clearThread(String roleId) async {
    _state = _state.withThread(AgentChatThread.empty(roleId));
    await _persist();
    notifyListeners();
  }

  /// Clears every persisted agent chat thread on this device.
  Future<void> clearAllThreads() async {
    _state = AgentChatsState.empty;
    await _persist();
    notifyListeners();
  }
}
