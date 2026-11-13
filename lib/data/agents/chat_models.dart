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
  });

  final String id;
  final AgentChatRole role;
  final String content;
  final DateTime createdAt;
  final AgentChatMessageKind kind;

  /// Linked [TradeProposal.id] when this assistant turn suggested a trade.
  final String? proposalId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind.name,
        if (proposalId != null) 'proposalId': proposalId,
      };

  factory AgentChatMessage.fromJson(Map<String, dynamic> json) {
    return AgentChatMessage(
      id: json['id'] as String? ?? '',
      role: AgentChatRoleX.parse(json['role'] as String?),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: AgentChatMessageKindX.parse(json['kind'] as String?),
      proposalId: json['proposalId'] as String?,
    );
  }

  static String newId() =>
      'm_${DateTime.now().microsecondsSinceEpoch}';
}

/// One persisted conversation per agent role.
class AgentChatThread {
  const AgentChatThread({
    required this.roleId,
    required this.messages,
    required this.updatedAt,
  });

  final String roleId;
  final List<AgentChatMessage> messages;
  final DateTime updatedAt;

  bool get isEmpty => messages.isEmpty;

  AgentChatThread copyWith({
    String? roleId,
    List<AgentChatMessage>? messages,
    DateTime? updatedAt,
  }) {
    return AgentChatThread(
      roleId: roleId ?? this.roleId,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'roleId': roleId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
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
    return AgentChatThread(
      roleId: json['roleId'] as String? ?? '',
      messages: messages,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory AgentChatThread.empty(String roleId) {
    return AgentChatThread(
      roleId: roleId,
      messages: const [],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AgentChatsState {
  const AgentChatsState({required this.threads});

  final List<AgentChatThread> threads;

  AgentChatThread threadFor(String roleId) {
    for (final t in threads) {
      if (t.roleId == roleId) return t;
    }
    return AgentChatThread.empty(roleId);
  }

  AgentChatsState withThread(AgentChatThread thread) {
    final next = <AgentChatThread>[
      for (final t in threads)
        if (t.roleId == thread.roleId) thread else t,
    ];
    if (!next.any((t) => t.roleId == thread.roleId)) {
      next.add(thread);
    }
    return AgentChatsState(threads: next);
  }

  Map<String, dynamic> toJson() => {
        'threads': threads.map((t) => t.toJson()).toList(),
      };

  factory AgentChatsState.fromJson(Map<String, dynamic> json) {
    final raw = json['threads'] as List? ?? const [];
    final threads = <AgentChatThread>[];
    for (final item in raw) {
      try {
        final t = AgentChatThread.fromJson(item as Map<String, dynamic>);
        if (t.roleId.isNotEmpty) threads.add(t);
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    return AgentChatsState(threads: threads);
  }

  static const empty = AgentChatsState(threads: []);
}
