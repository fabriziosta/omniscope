/// Who added a symbol to Markets → Invest interest.
enum InvestInterestSource {
  user,
  agent,
}

extension InvestInterestSourceX on InvestInterestSource {
  String get label => switch (this) {
        InvestInterestSource.user => 'You',
        InvestInterestSource.agent => 'Agent',
      };

  static InvestInterestSource parse(String? raw) {
    return InvestInterestSource.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => InvestInterestSource.user,
    );
  }
}

/// Per-symbol provenance for an Invest interest entry.
class InvestInterestProvenance {
  const InvestInterestProvenance({
    required this.source,
    this.roleId,
    this.addedAt,
  });

  final InvestInterestSource source;
  final String? roleId;
  final DateTime? addedAt;

  Map<String, dynamic> toJson() => {
        'source': source.name,
        if (roleId != null && roleId!.trim().isNotEmpty) 'roleId': roleId,
        if (addedAt != null) 'addedAt': addedAt!.toUtc().toIso8601String(),
      };

  factory InvestInterestProvenance.fromJson(Map<String, dynamic> json) {
    final addedRaw = json['addedAt'];
    return InvestInterestProvenance(
      source: InvestInterestSourceX.parse(json['source'] as String?),
      roleId: json['roleId'] is String ? (json['roleId'] as String).trim() : null,
      addedAt: addedRaw is String ? DateTime.tryParse(addedRaw)?.toUtc() : null,
    );
  }

  factory InvestInterestProvenance.user() => const InvestInterestProvenance(
        source: InvestInterestSource.user,
      );

  factory InvestInterestProvenance.agent({
    required String roleId,
    DateTime? addedAt,
  }) {
    return InvestInterestProvenance(
      source: InvestInterestSource.agent,
      roleId: roleId.trim().isEmpty ? null : roleId.trim(),
      addedAt: (addedAt ?? DateTime.now()).toUtc(),
    );
  }
}
