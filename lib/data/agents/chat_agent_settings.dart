import 'agent_app_settings.dart';
import 'models.dart';

/// Per-chat agent prefs: answer mood, specialty enablement, Autopilot portfolio.
class ChatAgentSettings {
  const ChatAgentSettings({
    this.answerMood = AgentAnswerMood.plain,
    this.answerMoodNote,
    this.disabledRoleIds = const {},
    this.autopilotExchangeId,
  });

  static const defaults = ChatAgentSettings();

  final AgentAnswerMood answerMood;
  final String? answerMoodNote;
  final Set<String> disabledRoleIds;
  final String? autopilotExchangeId;

  bool isRoleEnabled(String roleId) => !disabledRoleIds.contains(roleId);

  ChatAgentSettings copyWith({
    AgentAnswerMood? answerMood,
    String? answerMoodNote,
    bool clearAnswerMoodNote = false,
    Set<String>? disabledRoleIds,
    String? autopilotExchangeId,
    bool clearAutopilotExchangeId = false,
  }) {
    return ChatAgentSettings(
      answerMood: answerMood ?? this.answerMood,
      answerMoodNote: clearAnswerMoodNote
          ? null
          : (answerMoodNote ?? this.answerMoodNote),
      disabledRoleIds: disabledRoleIds ?? this.disabledRoleIds,
      autopilotExchangeId: clearAutopilotExchangeId
          ? null
          : (autopilotExchangeId ?? this.autopilotExchangeId),
    );
  }

  /// Seeds from legacy global [AgentAppSettings] chat-scoped fields.
  factory ChatAgentSettings.fromAppSettings(AgentAppSettings app) {
    return ChatAgentSettings(
      answerMood: app.answerMood,
      answerMoodNote: app.answerMoodNote,
      disabledRoleIds: Set<String>.from(app.disabledRoleIds),
      autopilotExchangeId: app.autopilotExchangeId,
    );
  }

  Map<String, dynamic> toJson() {
    final disabled = disabledRoleIds.toList()..sort();
    return {
      'answerMood': answerMood.name,
      if (answerMoodNote != null) 'answerMoodNote': answerMoodNote,
      if (disabled.isNotEmpty) 'disabledRoleIds': disabled,
      if (autopilotExchangeId != null && autopilotExchangeId!.trim().isNotEmpty)
        'autopilotExchangeId': autopilotExchangeId!.trim(),
    };
  }

  factory ChatAgentSettings.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final map = Map<String, dynamic>.from(raw);
    final moodRaw = map['answerMood'];
    final noteRaw = map['answerMoodNote'];
    final disabledRaw = map['disabledRoleIds'] as List? ?? const [];
    final exchangeRaw = map['autopilotExchangeId'];
    final exchange = exchangeRaw is String ? exchangeRaw.trim() : '';
    return ChatAgentSettings(
      answerMood: AgentAnswerMoodX.parse(moodRaw is String ? moodRaw : null),
      answerMoodNote: AgentAppSettings.normalizeAnswerMoodNote(
        noteRaw is String ? noteRaw : null,
      ),
      disabledRoleIds: {
        for (final id in disabledRaw)
          if (id is String && id.trim().isNotEmpty) id.trim(),
      },
      autopilotExchangeId: exchange.isEmpty ? null : exchange,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatAgentSettings) return false;
    if (other.answerMood != answerMood) return false;
    if (other.answerMoodNote != answerMoodNote) return false;
    if (other.autopilotExchangeId != autopilotExchangeId) return false;
    if (other.disabledRoleIds.length != disabledRoleIds.length) return false;
    for (final id in disabledRoleIds) {
      if (!other.disabledRoleIds.contains(id)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        answerMood,
        answerMoodNote,
        Object.hashAllUnordered(disabledRoleIds),
        autopilotExchangeId,
      );
}
