import 'package:flutter/foundation.dart';

import '../agents/models.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// High-level investing goal the user configures once.
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

/// User-level investment policy agents must respect (configurator surface).
class MandateSettings extends ChangeNotifier {
  MandateSettings({this.store});

  UserConfigStore? store;

  MandateGoal _goal = MandateGoal.learn;
  MandateHorizon _horizon = MandateHorizon.medium;
  MandateUniverse _universe = MandateUniverse.both;
  int _maxSymbolCount = 20;
  double? _maxNotionalPerProposal;
  int _maxOpenProposals = 3;
  AgentScheduleInterval _cadencePreference = AgentScheduleInterval.hour1;
  bool _ready = false;

  static const defaultMaxSymbolCount = 20;
  static const defaultMaxOpenProposals = 3;
  static const minSymbolCount = 1;
  static const maxSymbolCountCap = 100;
  static const minOpenProposals = 1;
  static const maxOpenProposalsCap = 20;

  MandateGoal get goal => _goal;
  MandateHorizon get horizon => _horizon;
  MandateUniverse get universe => _universe;
  int get maxSymbolCount => _maxSymbolCount;
  double? get maxNotionalPerProposal => _maxNotionalPerProposal;
  int get maxOpenProposals => _maxOpenProposals;
  AgentScheduleInterval get cadencePreference => _cadencePreference;
  bool get isReady => _ready;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _applySlice(this.store?.getSlice(UserConfigKeys.mandate));
    _ready = true;
    notifyListeners();
  }

  Future<void> setGoal(MandateGoal goal) async {
    if (_goal == goal) return;
    _goal = goal;
    notifyListeners();
    await _persist();
  }

  Future<void> setHorizon(MandateHorizon horizon) async {
    if (_horizon == horizon) return;
    _horizon = horizon;
    notifyListeners();
    await _persist();
  }

  Future<void> setUniverse(MandateUniverse universe) async {
    if (_universe == universe) return;
    _universe = universe;
    notifyListeners();
    await _persist();
  }

  Future<void> setMaxSymbolCount(int count) async {
    final clamped = count.clamp(minSymbolCount, maxSymbolCountCap);
    if (_maxSymbolCount == clamped) return;
    _maxSymbolCount = clamped;
    notifyListeners();
    await _persist();
  }

  Future<void> setMaxNotionalPerProposal(double? amount) async {
    final next = amount != null && amount > 0 ? amount : null;
    if (_maxNotionalPerProposal == next) return;
    _maxNotionalPerProposal = next;
    notifyListeners();
    await _persist();
  }

  Future<void> setMaxOpenProposals(int count) async {
    final clamped = count.clamp(minOpenProposals, maxOpenProposalsCap);
    if (_maxOpenProposals == clamped) return;
    _maxOpenProposals = clamped;
    notifyListeners();
    await _persist();
  }

  Future<void> setCadencePreference(AgentScheduleInterval interval) async {
    if (_cadencePreference == interval) return;
    _cadencePreference = interval;
    notifyListeners();
    await _persist();
  }

  /// Plain-language summary for agent tools and prompts.
  String toAgentSummary() {
    final notional = _maxNotionalPerProposal;
    final notionalText = notional == null
        ? 'no max notional'
        : 'max notional \$${notional.toStringAsFixed(notional == notional.roundToDouble() ? 0 : 2)}';
    return 'Mandate: goal=${_goal.name}, horizon=${_horizon.name}, '
        'universe=${_universe.name}, maxSymbols=$_maxSymbolCount, '
        '$notionalText, maxOpenProposals=$_maxOpenProposals, '
        'preferredCadence=${_cadencePreference.shortLabel}.';
  }

  Map<String, dynamic> toJson() => {
        'goal': _goal.name,
        'horizon': _horizon.name,
        'universe': _universe.name,
        'maxSymbolCount': _maxSymbolCount,
        if (_maxNotionalPerProposal != null)
          'maxNotionalPerProposal': _maxNotionalPerProposal,
        'maxOpenProposals': _maxOpenProposals,
        'cadencePreference': _cadencePreference.name,
      };

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.mandate, toJson());
  }

  void _applySlice(Object? slice) {
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);
    _goal = MandateGoalX.parse(map['goal'] as String?);
    _horizon = MandateHorizonX.parse(map['horizon'] as String?);
    _universe = MandateUniverseX.parse(map['universe'] as String?);
    final maxSymbols = (map['maxSymbolCount'] as num?)?.toInt();
    if (maxSymbols != null) {
      _maxSymbolCount =
          maxSymbols.clamp(minSymbolCount, maxSymbolCountCap);
    }
    final notional = (map['maxNotionalPerProposal'] as num?)?.toDouble();
    _maxNotionalPerProposal =
        notional != null && notional > 0 ? notional : null;
    final maxOpen = (map['maxOpenProposals'] as num?)?.toInt();
    if (maxOpen != null) {
      _maxOpenProposals =
          maxOpen.clamp(minOpenProposals, maxOpenProposalsCap);
    }
    _cadencePreference =
        AgentScheduleIntervalX.parse(map['cadencePreference'] as String?);
  }
}
