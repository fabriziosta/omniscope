import 'agent_app_settings.dart';
import 'agent_chat_repository.dart';
import 'chat_models.dart';

/// Ensures Schedule always has one persistent home chat for results / Confirm.
abstract final class ScheduleChatBinding {
  /// Creates or reuses the linked schedule chat and persists [scheduleChatId].
  ///
  /// Pins a newly created chat so it stays easy to find. Leaves user renames
  /// alone when the linked thread already exists.
  static Future<AgentChatThread> ensureChat({
    required AgentAppSettings app,
    required AgentChatRepository chats,
  }) async {
    final existingId = app.scheduleChatId?.trim();
    if (existingId != null && existingId.isNotEmpty) {
      final existing = chats.state.byId(existingId);
      if (existing != null) return existing;
    }

    final thread = await chats.createChat(
      title: AgentAppSettings.scheduleChatTitle,
    );
    await chats.setPinned(thread.chatId, pinned: true);
    await app.setSchedule(
      enabled: app.scheduleEnabled,
      scheduleChatId: thread.chatId,
    );
    return chats.threadFor(thread.chatId);
  }

  /// If [chatId] is the schedule home chat, disables Schedule and clears the
  /// link. Returns true when Schedule was stopped.
  static Future<bool> stopIfLinkedChatDeleted({
    required AgentAppSettings app,
    required String chatId,
  }) async {
    final linked = app.scheduleChatId?.trim();
    if (linked == null || linked.isEmpty || linked != chatId) {
      return false;
    }
    await app.stopScheduleForDeletedChat();
    return true;
  }

  /// Clears the schedule chat link (and disables Schedule) after all chats
  /// are wiped.
  static Future<void> stopAfterClearAllChats(AgentAppSettings app) async {
    if (!app.scheduleEnabled && app.scheduleChatId == null) return;
    await app.stopScheduleForDeletedChat();
  }
}
