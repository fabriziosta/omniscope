/// Kind of in-app attention alert (Activity → Alerts).
enum AppNotificationKind {
  scheduledRunCompleted,
  scheduledProposalPending,
  scheduledAutopilotDone,
  scheduledRunFailed,
  autopilotRiskHalt,

  /// Sticky setup reminder when no LLM API key is configured.
  configureAgents,
}

extension AppNotificationKindX on AppNotificationKind {
  String get label => switch (this) {
        AppNotificationKind.scheduledRunCompleted => 'Scheduled run',
        AppNotificationKind.scheduledProposalPending => 'Needs confirm',
        AppNotificationKind.scheduledAutopilotDone => 'Autopilot',
        AppNotificationKind.scheduledRunFailed => 'Scheduled failed',
        AppNotificationKind.autopilotRiskHalt => 'Autopilot halted',
        AppNotificationKind.configureAgents => 'Setup',
      };

  /// Sticky kinds stay unread and cannot be dismissed from the inbox.
  bool get isSticky => this == AppNotificationKind.configureAgents;

  static AppNotificationKind parse(String? raw) {
    return AppNotificationKind.values.firstWhere(
      (k) => k.name == raw,
      orElse: () => AppNotificationKind.scheduledRunCompleted,
    );
  }
}

enum AppNotificationStatus {
  active,
  dismissed,
}

extension AppNotificationStatusX on AppNotificationStatus {
  static AppNotificationStatus parse(String? raw) {
    return AppNotificationStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => AppNotificationStatus.active,
    );
  }
}

/// Durable in-app alert shown under Activity → Alerts.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.roleId,
    required this.createdAt,
    required this.title,
    required this.body,
    this.symbol,
    this.proposalId,
    this.chatId,
    this.read = false,
    this.status = AppNotificationStatus.active,
  });

  final String id;
  final AppNotificationKind kind;
  final String roleId;
  final DateTime createdAt;
  final String title;
  final String body;
  final String? symbol;
  final String? proposalId;
  final String? chatId;
  final bool read;
  final AppNotificationStatus status;

  bool get isActive => status == AppNotificationStatus.active;

  /// Sticky setup reminders stay in the inbox until Agents are configured.
  bool get isSticky => kind.isSticky;

  /// Stable id for the virtual configure-Agents reminder.
  static const configureAgentsId = 'an_configure_agents';

  /// Unread, non-dismissible reminder when no LLM endpoint is ready.
  static AppNotification configureAgentsReminder() {
    return AppNotification(
      id: configureAgentsId,
      kind: AppNotificationKind.configureAgents,
      roleId: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      title: 'Configure an API key',
      body:
          'Add an LLM provider key in Settings → Agents to start using Agents.',
      read: false,
    );
  }

  AppNotification copyWith({
    String? id,
    AppNotificationKind? kind,
    String? roleId,
    DateTime? createdAt,
    String? title,
    String? body,
    String? symbol,
    String? proposalId,
    String? chatId,
    bool? read,
    AppNotificationStatus? status,
    bool clearSymbol = false,
    bool clearProposalId = false,
    bool clearChatId = false,
  }) {
    return AppNotification(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      roleId: roleId ?? this.roleId,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      body: body ?? this.body,
      symbol: clearSymbol ? null : (symbol ?? this.symbol),
      proposalId: clearProposalId ? null : (proposalId ?? this.proposalId),
      chatId: clearChatId ? null : (chatId ?? this.chatId),
      read: read ?? this.read,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'roleId': roleId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'title': title,
        'body': body,
        if (symbol != null) 'symbol': symbol,
        if (proposalId != null) 'proposalId': proposalId,
        if (chatId != null) 'chatId': chatId,
        'read': read,
        'status': status.name,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      kind: AppNotificationKindX.parse(json['kind'] as String?),
      roleId: json['roleId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      symbol: json['symbol'] as String?,
      proposalId: json['proposalId'] as String?,
      chatId: json['chatId'] as String?,
      read: json['read'] as bool? ?? false,
      status: AppNotificationStatusX.parse(json['status'] as String?),
    );
  }

  static String newId() => 'an_${DateTime.now().microsecondsSinceEpoch}';
}
