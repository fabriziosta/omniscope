import '../agents/models.dart';

/// High-level investing goal the user configures per chat.
enum MandateGoal {
  learn,
  preserve,
  grow,
}

extension MandateGoalX on MandateGoal {
  String get label => switch (this) {
        MandateGoal.learn => 'Learn',
        MandateGoal.preserve => 'Preserve',
        MandateGoal.grow => 'Grow',
      };

  String get description => switch (this) {
        MandateGoal.learn => 'Practice and understand markets first',
        MandateGoal.preserve => 'Protect capital; favor smaller, safer moves',
        MandateGoal.grow => 'Seek growth within the risk rails below',
      };

  static MandateGoal parse(String? raw) {
    return MandateGoal.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MandateGoal.learn,
    );
  }
}

/// Time horizon for agent sizing and research tone.
enum MandateHorizon {
  short,
  medium,
  long,
}

extension MandateHorizonX on MandateHorizon {
  String get label => switch (this) {
        MandateHorizon.short => 'Short',
        MandateHorizon.medium => 'Medium',
        MandateHorizon.long => 'Long',
      };

  String get description => switch (this) {
        MandateHorizon.short => 'Days to weeks',
        MandateHorizon.medium => 'Months',
        MandateHorizon.long => 'Years',
      };

  static MandateHorizon parse(String? raw) {
    return MandateHorizon.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MandateHorizon.medium,
    );
  }
}

/// Which asset classes agents may put in Invest interest.
enum MandateUniverse {
  equities,
  crypto,
  both,
}

extension MandateUniverseX on MandateUniverse {
  String get label => switch (this) {
        MandateUniverse.equities => 'Equities',
        MandateUniverse.crypto => 'Crypto',
        MandateUniverse.both => 'Equities & crypto',
      };

  String get description => switch (this) {
        MandateUniverse.equities => 'Indices, ETFs, and stocks only',
        MandateUniverse.crypto => 'Spot crypto pairs only',
        MandateUniverse.both => 'Equities and spot crypto',
      };

  static MandateUniverse parse(String? raw) {
    return MandateUniverse.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MandateUniverse.both,
    );
  }
}

/// Per-chat investment policy agents must respect.
class ChatMandate {
  const ChatMandate({
    this.goal = MandateGoal.learn,
    this.horizon = MandateHorizon.medium,
    this.universe = MandateUniverse.both,
    this.maxSymbolCount = defaultMaxSymbolCount,
    this.maxNotionalPerProposal,
    this.maxOpenProposals = defaultMaxOpenProposals,
    this.maxAutopilotFillsPerDay = defaultMaxAutopilotFillsPerDay,
    this.maxDailyRealizedLoss,
    this.cadencePreference = AgentScheduleInterval.hour1,
  });

  static const defaults = ChatMandate();

  static const defaultMaxSymbolCount = 20;
  static const defaultMaxOpenProposals = 3;
  static const defaultMaxAutopilotFillsPerDay = 10;
  static const minSymbolCount = 1;
  static const maxSymbolCountCap = 100;
  static const minOpenProposals = 1;
  static const maxOpenProposalsCap = 20;
  static const minAutopilotFillsPerDay = 1;
  static const maxAutopilotFillsPerDayCap = 100;

  final MandateGoal goal;
  final MandateHorizon horizon;
  final MandateUniverse universe;
  final int maxSymbolCount;
  final double? maxNotionalPerProposal;
  final int maxOpenProposals;
  final int maxAutopilotFillsPerDay;
  final double? maxDailyRealizedLoss;
  final AgentScheduleInterval cadencePreference;

  ChatMandate copyWith({
    MandateGoal? goal,
    MandateHorizon? horizon,
    MandateUniverse? universe,
    int? maxSymbolCount,
    double? maxNotionalPerProposal,
    bool clearMaxNotionalPerProposal = false,
    int? maxOpenProposals,
    int? maxAutopilotFillsPerDay,
    double? maxDailyRealizedLoss,
    bool clearMaxDailyRealizedLoss = false,
    AgentScheduleInterval? cadencePreference,
  }) {
    return ChatMandate(
      goal: goal ?? this.goal,
      horizon: horizon ?? this.horizon,
      universe: universe ?? this.universe,
      maxSymbolCount: maxSymbolCount ?? this.maxSymbolCount,
      maxNotionalPerProposal: clearMaxNotionalPerProposal
          ? null
          : (maxNotionalPerProposal ?? this.maxNotionalPerProposal),
      maxOpenProposals: maxOpenProposals ?? this.maxOpenProposals,
      maxAutopilotFillsPerDay:
          maxAutopilotFillsPerDay ?? this.maxAutopilotFillsPerDay,
      maxDailyRealizedLoss: clearMaxDailyRealizedLoss
          ? null
          : (maxDailyRealizedLoss ?? this.maxDailyRealizedLoss),
      cadencePreference: cadencePreference ?? this.cadencePreference,
    );
  }

  /// Plain-language summary for agent tools and prompts.
  String toAgentSummary() {
    final notional = maxNotionalPerProposal;
    final notionalText = notional == null
        ? 'no max notional'
        : 'max notional \$${notional.toStringAsFixed(notional == notional.roundToDouble() ? 0 : 2)}';
    final loss = maxDailyRealizedLoss;
    final lossText = loss == null
        ? 'no daily loss stop'
        : 'max daily realized loss \$${loss.toStringAsFixed(loss == loss.roundToDouble() ? 0 : 2)}';
    return 'Mandate: goal=${goal.name}, horizon=${horizon.name}, '
        'universe=${universe.name}, maxSymbols=$maxSymbolCount, '
        '$notionalText, maxOpenProposals=$maxOpenProposals, '
        'maxAutopilotFillsPerDay=$maxAutopilotFillsPerDay, $lossText, '
        'preferredCadence=${cadencePreference.shortLabel}.';
  }

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        'horizon': horizon.name,
        'universe': universe.name,
        'maxSymbolCount': maxSymbolCount,
        if (maxNotionalPerProposal != null)
          'maxNotionalPerProposal': maxNotionalPerProposal,
        'maxOpenProposals': maxOpenProposals,
        'maxAutopilotFillsPerDay': maxAutopilotFillsPerDay,
        if (maxDailyRealizedLoss != null)
          'maxDailyRealizedLoss': maxDailyRealizedLoss,
        'cadencePreference': cadencePreference.name,
      };

  /// Parses a mandate map (chat thread or legacy global slice).
  factory ChatMandate.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final map = Map<String, dynamic>.from(raw);
    final goalRaw = map['goal'];
    final horizonRaw = map['horizon'];
    final universeRaw = map['universe'];
    final maxSymbolsRaw = map['maxSymbolCount'];
    final maxSymbols = maxSymbolsRaw is num ? maxSymbolsRaw.toInt() : null;
    final notionalRaw = map['maxNotionalPerProposal'];
    final notional = notionalRaw is num ? notionalRaw.toDouble() : null;
    final maxOpenRaw = map['maxOpenProposals'];
    final maxOpen = maxOpenRaw is num ? maxOpenRaw.toInt() : null;
    final fillsRaw = map['maxAutopilotFillsPerDay'];
    final fills = fillsRaw is num ? fillsRaw.toInt() : null;
    final lossRaw = map['maxDailyRealizedLoss'];
    final loss = lossRaw is num ? lossRaw.toDouble() : null;
    final cadenceRaw = map['cadencePreference'];
    return ChatMandate(
      goal: MandateGoalX.parse(goalRaw is String ? goalRaw : null),
      horizon: MandateHorizonX.parse(horizonRaw is String ? horizonRaw : null),
      universe:
          MandateUniverseX.parse(universeRaw is String ? universeRaw : null),
      maxSymbolCount: maxSymbols != null
          ? maxSymbols.clamp(minSymbolCount, maxSymbolCountCap)
          : defaultMaxSymbolCount,
      maxNotionalPerProposal:
          notional != null && notional > 0 ? notional : null,
      maxOpenProposals: maxOpen != null
          ? maxOpen.clamp(minOpenProposals, maxOpenProposalsCap)
          : defaultMaxOpenProposals,
      maxAutopilotFillsPerDay: fills != null
          ? fills.clamp(minAutopilotFillsPerDay, maxAutopilotFillsPerDayCap)
          : defaultMaxAutopilotFillsPerDay,
      maxDailyRealizedLoss: loss != null && loss > 0 ? loss : null,
      cadencePreference: AgentScheduleIntervalX.parse(
        cadenceRaw is String ? cadenceRaw : null,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMandate &&
        other.goal == goal &&
        other.horizon == horizon &&
        other.universe == universe &&
        other.maxSymbolCount == maxSymbolCount &&
        other.maxNotionalPerProposal == maxNotionalPerProposal &&
        other.maxOpenProposals == maxOpenProposals &&
        other.maxAutopilotFillsPerDay == maxAutopilotFillsPerDay &&
        other.maxDailyRealizedLoss == maxDailyRealizedLoss &&
        other.cadencePreference == cadencePreference;
  }

  @override
  int get hashCode => Object.hash(
        goal,
        horizon,
        universe,
        maxSymbolCount,
        maxNotionalPerProposal,
        maxOpenProposals,
        maxAutopilotFillsPerDay,
        maxDailyRealizedLoss,
        cadencePreference,
      );
}
