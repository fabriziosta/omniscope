import '../../core/formatting.dart';
import 'genkit/agent_peer_delegation.dart';

/// Who wrote a chat turn.
enum AgentChatRole {
  user,
  assistant,
  system,
}

extension AgentChatRoleX on AgentChatRole {
  static AgentChatRole parse(String? raw) {
    return AgentChatRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => AgentChatRole.user,
    );
  }
}

/// How the user turn was created.
enum AgentChatMessageKind {
  freeform,
  run,
}

extension AgentChatMessageKindX on AgentChatMessageKind {
  static AgentChatMessageKind parse(String? raw) {
    if (raw == 'run') return AgentChatMessageKind.run;
    return AgentChatMessageKind.freeform;
  }
}

class AgentChatMessage {
  const AgentChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.kind = AgentChatMessageKind.freeform,
    this.proposalId,
    this.modelId,
    this.generationMs,
    this.specialtyRoleIds = const [],
  });

  final String id;
  final AgentChatRole role;
  final String content;
  final DateTime createdAt;
  final AgentChatMessageKind kind;

  /// Linked [TradeProposal.id] when this assistant turn suggested a trade.
  final String? proposalId;

  /// Model id used to generate this assistant turn (e.g. `gemini-2.0-flash`).
  final String? modelId;

  /// Wall-clock time spent generating this assistant turn.
  final int? generationMs;

  /// Specialty role ids the orchestrator middleware selected for this turn.
  ///
  /// Empty for user messages, legacy threads, or when the orchestrator
  /// answered without delegating. When non-empty, order matches first
  /// delegation calls.
  final List<String> specialtyRoleIds;

  /// Muted footer for assistant turns:
  /// `Market Research · model · 1.2s · 5m ago`.
  String? get generationMetaLabel {
    final model = modelId?.trim();
    final ms = generationMs;
    final hasModel = model != null && model.isNotEmpty;
    final hasDuration = ms != null && ms >= 0;
    final specialty = specialtyRoleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .map(AgentPeerDelegation.chatMetaLabel)
        .where((label) => label.trim().isNotEmpty)
        .join(' + ');
    final hasSpecialty = specialty.isNotEmpty;
    // Show a sent-at label whenever other generation meta is present.
    final hasSentAt = hasSpecialty || hasModel || hasDuration;
    if (!hasSentAt) return null;
    final parts = <String>[
      if (hasSpecialty) specialty,
      if (hasModel) model,
      if (hasDuration) formatGenerationDuration(ms),
      formatRelativeTime(createdAt),
    ];
    return parts.join(' · ');
  }

  static String formatGenerationDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    final seconds = ms / 1000;
    if (seconds < 60) {
      final rounded = seconds >= 10
          ? seconds.round().toString()
          : seconds.toStringAsFixed(1);
      return '${rounded}s';
    }
    final minutes = ms ~/ 60000;
    final remSeconds = ((ms % 60000) / 1000).round();
    if (remSeconds == 0) return '${minutes}m';
    return '${minutes}m ${remSeconds}s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind.name,
        if (proposalId != null) 'proposalId': proposalId,
        if (modelId != null) 'modelId': modelId,
        if (generationMs != null) 'generationMs': generationMs,
        if (specialtyRoleIds.isNotEmpty) 'specialtyRoleIds': specialtyRoleIds,
      };

  factory AgentChatMessage.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['specialtyRoleIds'] as List? ?? const [];
    final specialtyRoleIds = <String>[
      for (final item in rawRoles)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    return AgentChatMessage(
      id: json['id'] as String? ?? '',
      role: AgentChatRoleX.parse(json['role'] as String?),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: AgentChatMessageKindX.parse(json['kind'] as String?),
      proposalId: json['proposalId'] as String?,
      modelId: json['modelId'] as String?,
      generationMs: (json['generationMs'] as num?)?.toInt(),
      specialtyRoleIds: specialtyRoleIds,
    );
  }

  static String newId() => 'm_${DateTime.now().microsecondsSinceEpoch}';
}

/// One agent-agnostic conversation (orchestrator routes specialists).
class AgentChatThread {
  const AgentChatThread({
    required this.chatId,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.pinned = false,
    this.autopilotEnabled = false,
    this.memoryEnabled = true,
    this.legacyRoleId,
  });

  final String chatId;
  final String title;
  final List<AgentChatMessage> messages;
  final DateTime updatedAt;

  /// When true, the Agents sidebar keeps this chat above unpinned ones.
  final bool pinned;

  /// When true, risk-approved trades / add-only Invest interest auto-apply
  /// for this chat only (Confirm still gates other chats).
  final bool autopilotEnabled;

  /// When true, this chat may read/write the shared agent memory store.
  /// Default on; omit in JSON when true, write `false` when off.
  final bool memoryEnabled;

  /// Present when migrated from a legacy per-role thread.
  final String? legacyRoleId;

  bool get isEmpty => messages.isEmpty;

  /// User/assistant turns as plain text for clipboard export.
  String get plainTextExchange {
    final parts = <String>[];
    for (final message in messages) {
      if (message.role == AgentChatRole.system) continue;
      final content = message.content.trim();
      if (content.isEmpty) continue;
      final label = switch (message.role) {
        AgentChatRole.user => 'You',
        AgentChatRole.assistant => 'Agent',
        AgentChatRole.system => 'System',
      };
      final sentAt = message.createdAt.toUtc().toIso8601String();
      parts.add('$label [$sentAt]:\n$content');
    }
    return parts.join('\n\n');
  }

  AgentChatThread copyWith({
    String? chatId,
    String? title,
    List<AgentChatMessage>? messages,
    DateTime? updatedAt,
    bool? pinned,
    bool? autopilotEnabled,
    bool? memoryEnabled,
    String? legacyRoleId,
    bool clearLegacyRoleId = false,
  }) {
    return AgentChatThread(
      chatId: chatId ?? this.chatId,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      autopilotEnabled: autopilotEnabled ?? this.autopilotEnabled,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      legacyRoleId:
          clearLegacyRoleId ? null : (legacyRoleId ?? this.legacyRoleId),
    );
  }

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        if (pinned) 'pinned': true,
        if (autopilotEnabled) 'autopilotEnabled': true,
        // Default on: only persist when explicitly off.
        if (!memoryEnabled) 'memoryEnabled': false,
        if (legacyRoleId != null) 'legacyRoleId': legacyRoleId,
        // Keep roleId for older readers during transition.
        if (legacyRoleId != null) 'roleId': legacyRoleId,
      };

  factory AgentChatThread.fromJson(Map<String, dynamic> json) {
    final raw = json['messages'] as List? ?? const [];
    final messages = <AgentChatMessage>[];
    for (final item in raw) {
      try {
        messages.add(
          AgentChatMessage.fromJson(item as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    final legacyRoleId = json['legacyRoleId'] as String? ??
        (json['chatId'] == null ? json['roleId'] as String? : null);
    final chatId = (json['chatId'] as String?)?.trim();
    final resolvedId = (chatId != null && chatId.isNotEmpty)
        ? chatId
        : (legacyRoleId != null && legacyRoleId.isNotEmpty
            ? 'legacy_$legacyRoleId'
            : '');
    final title = (json['title'] as String?)?.trim();
    return AgentChatThread(
      chatId: resolvedId,
      title: (title != null && title.isNotEmpty)
          ? title
          : (legacyRoleId != null && legacyRoleId.isNotEmpty
              ? legacyRoleId
              : 'Chat'),
      messages: messages,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      pinned: json['pinned'] == true,
      autopilotEnabled: json['autopilotEnabled'] == true,
      memoryEnabled: json['memoryEnabled'] != false,
      legacyRoleId: legacyRoleId,
    );
  }

  factory AgentChatThread.empty({
    required String chatId,
    String title = 'New chat',
    bool autopilotEnabled = false,
    bool memoryEnabled = true,
  }) {
    return AgentChatThread(
      chatId: chatId,
      title: title,
      messages: const [],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      autopilotEnabled: autopilotEnabled,
      memoryEnabled: memoryEnabled,
    );
  }

  static String newChatId() => 'c_${DateTime.now().microsecondsSinceEpoch}';
}

class AgentChatsState {
  const AgentChatsState({required this.threads});

  final List<AgentChatThread> threads;

  AgentChatThread? byId(String chatId) {
    for (final t in threads) {
      if (t.chatId == chatId) return t;
    }
    return null;
  }

  /// Prefer exact [chatId]; fall back to legacy role-keyed thread.
  AgentChatThread threadFor(String chatId) {
    return byId(chatId) ??
        AgentChatThread.empty(chatId: chatId, title: 'New chat');
  }

  /// Pinned chats first, then newest [AgentChatThread.updatedAt].
  List<AgentChatThread> get sortedByUpdated {
    final list = List<AgentChatThread>.from(threads);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  AgentChatsState withThread(AgentChatThread thread) {
    final next = <AgentChatThread>[
      for (final t in threads)
        if (t.chatId == thread.chatId) thread else t,
    ];
    if (!next.any((t) => t.chatId == thread.chatId)) {
      next.add(thread);
    }
    return AgentChatsState(threads: next);
  }

  AgentChatsState withoutThread(String chatId) {
    return AgentChatsState(
      threads: [for (final t in threads) if (t.chatId != chatId) t],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'threads': threads.map((t) => t.toJson()).toList(),
      };

  factory AgentChatsState.fromJson(Map<String, dynamic> json) {
    final raw = json['threads'] as List? ?? const [];
    final threads = <AgentChatThread>[];
    for (final item in raw) {
      try {
        final t = AgentChatThread.fromJson(item as Map<String, dynamic>);
        if (t.chatId.isNotEmpty) threads.add(t);
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    return AgentChatsState(threads: threads);
  }

  static const empty = AgentChatsState(threads: []);
}
