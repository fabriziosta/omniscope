/// Real in-app events for the Activity tab timeline (no simulated swarm).
enum AgentActivityKind {
  messageSent,
  proposalParsed,
  proposalConfirmed,
  proposalDismissed,
  autopilotSubmitted,
  orderAck,
  orderFailed,
  runBlockedNoExchange,
  scheduledRun,
}

extension AgentActivityKindX on AgentActivityKind {
  String get label => switch (this) {
        AgentActivityKind.messageSent => 'Message sent',
        AgentActivityKind.proposalParsed => 'Proposal',
        AgentActivityKind.proposalConfirmed => 'Confirmed',
        AgentActivityKind.proposalDismissed => 'Dismissed',
        AgentActivityKind.autopilotSubmitted => 'Autopilot',
        AgentActivityKind.orderAck => 'Order placed',
        AgentActivityKind.orderFailed => 'Order failed',
        AgentActivityKind.runBlockedNoExchange => 'Blocked',
        AgentActivityKind.scheduledRun => 'Scheduled',
      };

  static AgentActivityKind parse(String? raw) {
    return AgentActivityKind.values.firstWhere(
      (k) => k.name == raw,
      orElse: () => AgentActivityKind.messageSent,
    );
  }
}

class AgentActivityEvent {
  const AgentActivityEvent({
    required this.id,
    required this.kind,
    required this.roleId,
    required this.createdAt,
    this.exchangeId,
    this.proposalId,
    this.messageId,
    this.symbol,
    this.summary = '',
  });

  final String id;
  final AgentActivityKind kind;
  final String roleId;
  final DateTime createdAt;
  final String? exchangeId;
  final String? proposalId;
  final String? messageId;
  final String? symbol;
  final String summary;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'roleId': roleId,
        'createdAt': createdAt.toIso8601String(),
        if (exchangeId != null) 'exchangeId': exchangeId,
        if (proposalId != null) 'proposalId': proposalId,
        if (messageId != null) 'messageId': messageId,
        if (symbol != null) 'symbol': symbol,
        'summary': summary,
      };

  factory AgentActivityEvent.fromJson(Map<String, dynamic> json) {
    return AgentActivityEvent(
      id: json['id'] as String? ?? '',
      kind: AgentActivityKindX.parse(json['kind'] as String?),
      roleId: json['roleId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      exchangeId: json['exchangeId'] as String?,
      proposalId: json['proposalId'] as String?,
      messageId: json['messageId'] as String?,
      symbol: json['symbol'] as String?,
      summary: json['summary'] as String? ?? '',
    );
  }

  static String newId() => 'ae_${DateTime.now().microsecondsSinceEpoch}';
}
