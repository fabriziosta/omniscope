import 'dart:convert';

import '../trading/order_models.dart';

/// Lifecycle of an agent-suggested trade (Practice or live).
enum TradeProposalStatus {
  pending,
  confirmed,
  dismissed,
  executed,
  failed,
  skipped,
}

extension TradeProposalStatusX on TradeProposalStatus {
  String get label => switch (this) {
        TradeProposalStatus.pending => 'Pending',
        TradeProposalStatus.confirmed => 'Confirmed',
        TradeProposalStatus.dismissed => 'Dismissed',
        TradeProposalStatus.executed => 'Executed',
        TradeProposalStatus.failed => 'Failed',
        TradeProposalStatus.skipped => 'Skipped',
      };

  /// Plain-language status for the Activity dashboard.
  String get dashboardLabel => switch (this) {
        TradeProposalStatus.pending => 'Needs confirmation',
        TradeProposalStatus.executed => 'Accepted',
        TradeProposalStatus.dismissed => 'Refused',
        TradeProposalStatus.confirmed => 'Confirmed',
        TradeProposalStatus.failed => 'Failed',
        TradeProposalStatus.skipped => 'Skipped',
      };

  static TradeProposalStatus parse(String? raw) {
    return TradeProposalStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => TradeProposalStatus.pending,
    );
  }
}

/// Canonical LLM JSON keys for trade proposals (snake_case).
///
/// Keep in sync with `agents/omniscope_agents/trade_schema.py` (`TRADE_JSON_KEYS`).
/// Prompt prose differs by surface (Flutter = live; CLI = paper); only keys match.
abstract final class TradeProposalLlmSchema {
  static const List<String> canonicalLlmKeys = [
    'ticker',
    'action',
    'quantity',
    'rationale',
    'risk_approved',
  ];
}

/// Suggested order from an agent (Practice or live portfolio).
enum TradeProposalSide {
  buy,
  sell,
  hold,
}

extension TradeProposalSideX on TradeProposalSide {
  String get label => switch (this) {
        TradeProposalSide.buy => 'Buy',
        TradeProposalSide.sell => 'Sell',
        TradeProposalSide.hold => 'Hold',
      };

  OrderSide? get orderSide => switch (this) {
        TradeProposalSide.buy => OrderSide.buy,
        TradeProposalSide.sell => OrderSide.sell,
        TradeProposalSide.hold => null,
      };

  static TradeProposalSide? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'buy' => TradeProposalSide.buy,
      'sell' => TradeProposalSide.sell,
      'hold' => TradeProposalSide.hold,
      _ => null,
    };
  }
}

class TradeProposal {
  const TradeProposal({
    required this.id,
    required this.roleId,
    required this.exchangeId,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.rationale,
    required this.riskApproved,
    required this.status,
    required this.createdAt,
    this.sourceMessageId,
    this.executionError,
    this.orderId,
    this.autopilot = false,
  });

  final String id;
  final String roleId;
  final String exchangeId;
  final String symbol;
  final TradeProposalSide side;
  final double quantity;
  final String rationale;
  final bool riskApproved;
  final TradeProposalStatus status;
  final DateTime createdAt;
  final String? sourceMessageId;
  final String? executionError;
  final String? orderId;
  final bool autopilot;

  bool get isActionable =>
      status == TradeProposalStatus.pending &&
      side != TradeProposalSide.hold &&
      quantity > 0 &&
      riskApproved;

  TradeProposal copyWith({
    String? id,
    String? roleId,
    String? exchangeId,
    String? symbol,
    TradeProposalSide? side,
    double? quantity,
    String? rationale,
    bool? riskApproved,
    TradeProposalStatus? status,
    DateTime? createdAt,
    String? sourceMessageId,
    String? executionError,
    String? orderId,
    bool? autopilot,
    bool clearExecutionError = false,
    bool clearOrderId = false,
  }) {
    return TradeProposal(
      id: id ?? this.id,
      roleId: roleId ?? this.roleId,
      exchangeId: exchangeId ?? this.exchangeId,
      symbol: symbol ?? this.symbol,
      side: side ?? this.side,
      quantity: quantity ?? this.quantity,
      rationale: rationale ?? this.rationale,
      riskApproved: riskApproved ?? this.riskApproved,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      executionError: clearExecutionError
          ? null
          : (executionError ?? this.executionError),
      orderId: clearOrderId ? null : (orderId ?? this.orderId),
      autopilot: autopilot ?? this.autopilot,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roleId': roleId,
        'exchangeId': exchangeId,
        'symbol': symbol,
        'side': side.name,
        'quantity': quantity,
        'rationale': rationale,
        'riskApproved': riskApproved,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
        if (executionError != null) 'executionError': executionError,
        if (orderId != null) 'orderId': orderId,
        'autopilot': autopilot,
      };

  factory TradeProposal.fromJson(Map<String, dynamic> json) {
    return TradeProposal(
      id: json['id'] as String? ?? '',
      roleId: json['roleId'] as String? ?? '',
      exchangeId: json['exchangeId'] as String? ?? '',
      symbol: (json['symbol'] as String? ?? json['ticker'] as String? ?? '')
          .toUpperCase(),
      side: TradeProposalSideX.tryParse(
            json['side'] as String? ?? json['action'] as String?,
          ) ??
          TradeProposalSide.hold,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      rationale: json['rationale'] as String? ?? '',
      riskApproved: json['riskApproved'] as bool? ??
          json['risk_approved'] as bool? ??
          false,
      status: TradeProposalStatusX.parse(json['status'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceMessageId: json['sourceMessageId'] as String?,
      executionError: json['executionError'] as String?,
      orderId: json['orderId'] as String?,
      autopilot: json['autopilot'] as bool? ?? false,
    );
  }

  static String newId() => 'tp_${DateTime.now().microsecondsSinceEpoch}';

  /// Build from LLM JSON fields (ticker/action or symbol/side).
  factory TradeProposal.fromLlmJson(
    Map<String, dynamic> json, {
    required String roleId,
    required String exchangeId,
    String? sourceMessageId,
    String? fallbackSymbol,
  }) {
    final symbol = (json['symbol'] as String? ??
            json['ticker'] as String? ??
            fallbackSymbol ??
            '')
        .trim()
        .toUpperCase();
    final side = TradeProposalSideX.tryParse(
          json['side'] as String? ?? json['action'] as String?,
        ) ??
        TradeProposalSide.hold;
    final qty = (json['quantity'] as num?)?.toDouble() ?? 0;
    final rationale = (json['rationale'] as String? ?? '').trim();
    final risk = json['riskApproved'] as bool? ??
        json['risk_approved'] as bool? ??
        false;

    return TradeProposal(
      id: newId(),
      roleId: roleId,
      exchangeId: exchangeId,
      symbol: symbol,
      side: side,
      quantity: qty,
      rationale: rationale,
      riskApproved: risk,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.now().toUtc(),
      sourceMessageId: sourceMessageId,
    );
  }
}

/// Extracts a fenced or bare JSON trade object from assistant text.
class TradeProposalParser {
  TradeProposalParser._();

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
      if (parsed != null && _looksLikeTrade(parsed)) return parsed;
    }

    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = _tryDecodeObject(content.substring(start, end + 1));
      if (parsed != null && _looksLikeTrade(parsed)) return parsed;
    }
    return null;
  }

  static bool _looksLikeTrade(Map<String, dynamic> json) {
    final hasSymbol = (json['symbol'] ?? json['ticker']) != null;
    final hasAction = (json['side'] ?? json['action']) != null;
    return hasSymbol && hasAction;
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
