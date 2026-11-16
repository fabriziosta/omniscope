import 'dart:convert';

/// Lifecycle of an agent-suggested Invest interest change.
enum InvestInterestProposalStatus {
  pending,
  confirmed,
  dismissed,
  failed,
}

extension InvestInterestProposalStatusX on InvestInterestProposalStatus {
  String get label => switch (this) {
        InvestInterestProposalStatus.pending => 'Pending',
        InvestInterestProposalStatus.confirmed => 'Confirmed',
        InvestInterestProposalStatus.dismissed => 'Dismissed',
        InvestInterestProposalStatus.failed => 'Failed',
      };

  String get dashboardLabel => switch (this) {
        InvestInterestProposalStatus.pending => 'Needs confirmation',
        InvestInterestProposalStatus.confirmed => 'Accepted',
        InvestInterestProposalStatus.dismissed => 'Refused',
        InvestInterestProposalStatus.failed => 'Failed',
      };

  static InvestInterestProposalStatus parse(String? raw) {
    return InvestInterestProposalStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => InvestInterestProposalStatus.pending,
    );
  }
}

/// Canonical LLM / tool keys for Invest interest diffs.
abstract final class InvestInterestProposalLlmSchema {
  static const List<String> canonicalLlmKeys = [
    'add',
    'remove',
    'set',
    'rationale',
  ];
}

/// Suggested Invest interest list change from an agent (Confirm to apply).
class InvestInterestProposal {
  const InvestInterestProposal({
    required this.id,
    required this.roleId,
    required this.add,
    required this.remove,
    required this.rationale,
    required this.status,
    required this.createdAt,
    this.setSymbols,
    this.chatId,
    this.sourceMessageId,
    this.applyError,
  });

  final String id;
  final String roleId;
  final List<String> add;
  final List<String> remove;

  /// When non-null, Confirm replaces the list with this ordered set
  /// (still subject to mandate max symbol count).
  final List<String>? setSymbols;
  final String rationale;
  final InvestInterestProposalStatus status;
  final DateTime createdAt;
  final String? chatId;
  final String? sourceMessageId;
  final String? applyError;

  bool get isActionable =>
      status == InvestInterestProposalStatus.pending &&
      (add.isNotEmpty ||
          remove.isNotEmpty ||
          (setSymbols != null && setSymbols!.isNotEmpty));

  String get summaryLabel {
    if (setSymbols != null) {
      return 'Set invest interest (${setSymbols!.length})';
    }
    final parts = <String>[];
    if (add.isNotEmpty) parts.add('Add ${add.join(', ')}');
    if (remove.isNotEmpty) parts.add('Remove ${remove.join(', ')}');
    return parts.isEmpty ? 'Invest interest change' : parts.join(' · ');
  }

  InvestInterestProposal copyWith({
    String? id,
    String? roleId,
    List<String>? add,
    List<String>? remove,
    List<String>? setSymbols,
    String? rationale,
    InvestInterestProposalStatus? status,
    DateTime? createdAt,
    String? chatId,
    String? sourceMessageId,
    String? applyError,
    bool clearSetSymbols = false,
    bool clearApplyError = false,
  }) {
    return InvestInterestProposal(
      id: id ?? this.id,
      roleId: roleId ?? this.roleId,
      add: add ?? this.add,
      remove: remove ?? this.remove,
      setSymbols:
          clearSetSymbols ? null : (setSymbols ?? this.setSymbols),
      rationale: rationale ?? this.rationale,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      chatId: chatId ?? this.chatId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      applyError:
          clearApplyError ? null : (applyError ?? this.applyError),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roleId': roleId,
        'add': add,
        'remove': remove,
        if (setSymbols != null) 'set': setSymbols,
        'rationale': rationale,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (chatId != null) 'chatId': chatId,
        if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
        if (applyError != null) 'applyError': applyError,
      };

  factory InvestInterestProposal.fromJson(Map<String, dynamic> json) {
    return InvestInterestProposal(
      id: json['id'] as String? ?? '',
      roleId: json['roleId'] as String? ?? '',
      add: _readSymbolList(json['add']),
      remove: _readSymbolList(json['remove']),
      setSymbols: json.containsKey('set')
          ? _readSymbolList(json['set'])
          : null,
      rationale: json['rationale'] as String? ?? '',
      status: InvestInterestProposalStatusX.parse(json['status'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      chatId: json['chatId'] as String?,
      sourceMessageId: json['sourceMessageId'] as String?,
      applyError: json['applyError'] as String?,
    );
  }

  static String newId() => 'iip_${DateTime.now().microsecondsSinceEpoch}';

  factory InvestInterestProposal.fromToolInput(
    Map<String, dynamic> json, {
    required String roleId,
    String? chatId,
    String? sourceMessageId,
  }) {
    final setRaw = json['set'] ?? json['symbols'];
    final hasSet = setRaw is List;
    return InvestInterestProposal(
      id: newId(),
      roleId: roleId,
      add: _readSymbolList(json['add']),
      remove: _readSymbolList(json['remove']),
      setSymbols: hasSet ? _readSymbolList(setRaw) : null,
      rationale: (json['rationale'] as String? ?? '').trim(),
      status: InvestInterestProposalStatus.pending,
      createdAt: DateTime.now().toUtc(),
      chatId: chatId,
      sourceMessageId: sourceMessageId,
    );
  }

  static List<String> _readSymbolList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item?.toString().trim().toUpperCase() ?? '';
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }
}

/// Extracts a fenced or bare Invest interest JSON object from assistant text.
class InvestInterestProposalParser {
  InvestInterestProposalParser._();

  static final _fencedJson = RegExp(
    r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
    caseSensitive: false,
  );

  static Map<String, dynamic>? extractJsonMap(String content) {
    final fenced = _fencedJson.firstMatch(content);
    final candidates = <String>[
      if (fenced != null) fenced.group(1)!,
      content.trim(),
    ];

    for (final raw in candidates) {
      final parsed = _tryDecodeObject(raw);
      if (parsed != null && _looksLikeInvestInterest(parsed)) return parsed;
    }

    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = _tryDecodeObject(content.substring(start, end + 1));
      if (parsed != null && _looksLikeInvestInterest(parsed)) return parsed;
    }
    return null;
  }

  static bool _looksLikeInvestInterest(Map<String, dynamic> json) {
    final type = (json['type'] as String?)?.trim().toLowerCase();
    if (type == 'invest_interest' || type == 'investInterest') return true;
    final hasAdd = json['add'] is List;
    final hasRemove = json['remove'] is List;
    final hasSet = json['set'] is List || json['symbols'] is List;
    final hasRationale = json['rationale'] != null;
    // Distinguish from trade JSON (ticker/action).
    final looksLikeTrade =
        (json['ticker'] ?? json['symbol']) != null &&
            (json['side'] ?? json['action']) != null;
    if (looksLikeTrade) return false;
    return hasRationale && (hasAdd || hasRemove || hasSet);
  }

  static Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
