/// Provenance for one shared agent-memory fact.
enum AgentMemorySource {
  user,
  agent;

  static AgentMemorySource fromJson(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    return s == 'agent' ? AgentMemorySource.agent : AgentMemorySource.user;
  }

  String get label => switch (this) {
        AgentMemorySource.user => 'You',
        AgentMemorySource.agent => 'Agent',
      };
}

/// One durable fact in the shared cross-chat memory store.
class AgentMemoryFact {
  const AgentMemoryFact({
    required this.id,
    required this.text,
    required this.updatedAt,
    this.source = AgentMemorySource.user,
  });

  final String id;
  final String text;
  final DateTime updatedAt;
  final AgentMemorySource source;

  AgentMemoryFact copyWith({
    String? id,
    String? text,
    DateTime? updatedAt,
    AgentMemorySource? source,
  }) {
    return AgentMemoryFact(
      id: id ?? this.id,
      text: text ?? this.text,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
        'source': source.name,
      };

  factory AgentMemoryFact.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final text = (json['text'] as String?)?.trim() ?? '';
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return AgentMemoryFact(
      id: id,
      text: text,
      updatedAt: updatedAt.toUtc(),
      source: AgentMemorySource.fromJson(json['source']),
    );
  }

  static String newId() =>
      'm_${DateTime.now().toUtc().microsecondsSinceEpoch}';
}
