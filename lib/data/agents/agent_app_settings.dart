import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'models.dart';

/// Optional per-role model override for advanced users.
class AgentRoleOverride {
  const AgentRoleOverride({
    required this.roleId,
    this.provider,
    this.modelId,
  });

  final String roleId;
  final LlmProvider? provider;
  final String? modelId;

  bool get hasModelOverride =>
      provider != null && (modelId?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toJson() => {
        'roleId': roleId,
        if (provider != null) 'provider': provider!.name,
        if (modelId != null && modelId!.trim().isNotEmpty) 'modelId': modelId,
      };

  factory AgentRoleOverride.fromJson(Map<String, dynamic> json) {
    final rawProvider = json['provider'] as String?;
    LlmProvider? provider;
    if (rawProvider != null) {
      provider = LlmProvider.values.firstWhere(
        (p) => p.name == rawProvider,
        orElse: () => LlmProvider.gemini,
      );
    }
    return AgentRoleOverride(
      roleId: json['roleId'] as String? ?? '',
      provider: provider,
      modelId: json['modelId'] as String?,
    );
  }
}

/// Global Autopilot / Schedule / role enable — Settings → Agents (advanced).
class AgentAppSettings extends ChangeNotifier {
  AgentAppSettings({this.store});

  UserConfigStore? store;

  /// Max length for the optional free-text mood note.
  static const maxAnswerMoodNoteLength = 200;

  Set<String> _disabledRoleIds = {};
  final Map<String, AgentRoleOverride> _overrides = {};
  var _autopilotEnabled = false;
  String? _autopilotExchangeId;
  double? _autopilotMaxNotional;
  var _autopilotMaxOpenProposals = 3;
  var _scheduleEnabled = false;
  var _scheduleInterval = AgentScheduleInterval.hour1;
  List<String> _scheduleSymbols = const [];
  var _scheduleUseInvestInterest = true;
  DateTime? _scheduleLastRunAt;
  var _answerMood = AgentAnswerMood.plain;
  String? _answerMoodNote;
  bool _ready = false;

  bool get isReady => _ready;
  bool get autopilotEnabled => _autopilotEnabled;
  String? get autopilotExchangeId => _autopilotExchangeId;
  double? get autopilotMaxNotional => _autopilotMaxNotional;
  int get autopilotMaxOpenProposals => _autopilotMaxOpenProposals;
  bool get scheduleEnabled => _scheduleEnabled;
  AgentScheduleInterval get scheduleInterval => _scheduleInterval;
  List<String> get scheduleSymbols => _scheduleSymbols;
  bool get scheduleUseInvestInterest => _scheduleUseInvestInterest;
  DateTime? get scheduleLastRunAt => _scheduleLastRunAt;
  AgentAnswerMood get answerMood => _answerMood;
  String? get answerMoodNote => _answerMoodNote;
  Set<String> get disabledRoleIds => Set.unmodifiable(_disabledRoleIds);

  /// Trim + length-cap a mood note; empty becomes null.
  static String? normalizeAnswerMoodNote(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= maxAnswerMoodNoteLength) return trimmed;
    return trimmed.substring(0, maxAnswerMoodNoteLength);
  }

  bool isRoleEnabled(String roleId) => !_disabledRoleIds.contains(roleId);

  AgentRoleOverride? overrideFor(String roleId) => _overrides[roleId];

  bool isScheduleDue(DateTime now) {
    if (!_scheduleEnabled) return false;
    if (!_scheduleUseInvestInterest && _scheduleSymbols.isEmpty) {
      return false;
    }
    final last = _scheduleLastRunAt;
    if (last == null) return true;
    final elapsed = now.toUtc().difference(last.toUtc());
    return !elapsed.isNegative && elapsed >= _scheduleInterval.duration;
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.agentApp);
    if (slice is! Map) {
      _resetDefaults();
    } else {
      try {
        _readJson(Map<String, dynamic>.from(slice));
      } catch (_) {
        _resetDefaults();
      }
    }
    _ready = true;
    notifyListeners();
  }

  void _resetDefaults() {
    _disabledRoleIds = {};
    _overrides.clear();
    _autopilotEnabled = false;
    _autopilotExchangeId = null;
    _autopilotMaxNotional = null;
    _autopilotMaxOpenProposals = 3;
    _scheduleEnabled = false;
    _scheduleInterval = AgentScheduleInterval.hour1;
    _scheduleSymbols = const [];
    _scheduleUseInvestInterest = true;
    _scheduleLastRunAt = null;
    _answerMood = AgentAnswerMood.plain;
    _answerMoodNote = null;
  }

  void _readJson(Map<String, dynamic> json) {
    final disabled = json['disabledRoleIds'] as List? ?? const [];
    _disabledRoleIds = {
      for (final id in disabled)
        if (id is String && id.isNotEmpty) id,
    };
    _overrides.clear();
    final rawOverrides = json['overrides'] as List? ?? const [];
    for (final item in rawOverrides) {
      if (item is! Map) continue;
      final o = AgentRoleOverride.fromJson(Map<String, dynamic>.from(item));
      if (o.roleId.isNotEmpty) _overrides[o.roleId] = o;
    }
    _autopilotEnabled = json['autopilotEnabled'] is bool
        ? json['autopilotEnabled'] as bool
        : false;
    _autopilotExchangeId = json['autopilotExchangeId'] is String
        ? json['autopilotExchangeId'] as String
        : null;
    final maxNotional = json['autopilotMaxNotional'];
    _autopilotMaxNotional =
        maxNotional is num ? maxNotional.toDouble() : null;
    final maxOpen = json['autopilotMaxOpenProposals'];
    _autopilotMaxOpenProposals = maxOpen is num ? maxOpen.toInt() : 3;
    _scheduleEnabled = json['scheduleEnabled'] is bool
        ? json['scheduleEnabled'] as bool
        : false;
    final intervalRaw = json['scheduleInterval'];
    _scheduleInterval = AgentScheduleIntervalX.parse(
      intervalRaw is String ? intervalRaw : null,
    );
    _scheduleSymbols = normalizeScheduleSymbols(
      (json['scheduleSymbols'] as List? ?? const []).whereType<String>(),
    );
    _scheduleUseInvestInterest = json['scheduleUseInvestInterest'] is bool
        ? json['scheduleUseInvestInterest'] as bool
        : true;
    final last = json['scheduleLastRunAt'];
    _scheduleLastRunAt =
        last is String ? DateTime.tryParse(last) : null;
    final moodRaw = json['answerMood'];
    _answerMood = AgentAnswerMoodX.parse(moodRaw is String ? moodRaw : null);
    final noteRaw = json['answerMoodNote'];
    _answerMoodNote =
        normalizeAnswerMoodNote(noteRaw is String ? noteRaw : null);
  }

  Map<String, dynamic> toJson() => {
        'disabledRoleIds': _disabledRoleIds.toList()..sort(),
        'overrides': [for (final o in _overrides.values) o.toJson()],
        'autopilotEnabled': _autopilotEnabled,
        if (_autopilotExchangeId != null)
          'autopilotExchangeId': _autopilotExchangeId,
        if (_autopilotMaxNotional != null)
          'autopilotMaxNotional': _autopilotMaxNotional,
        'autopilotMaxOpenProposals': _autopilotMaxOpenProposals,
        'scheduleEnabled': _scheduleEnabled,
        'scheduleInterval': _scheduleInterval.name,
        'scheduleSymbols': _scheduleSymbols,
        'scheduleUseInvestInterest': _scheduleUseInvestInterest,
        if (_scheduleLastRunAt != null)
          'scheduleLastRunAt': _scheduleLastRunAt!.toUtc().toIso8601String(),
        'answerMood': _answerMood.name,
        if (_answerMoodNote != null) 'answerMoodNote': _answerMoodNote,
      };

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.agentApp, toJson());
  }

  /// Reset Autopilot, Schedule, role enable, and overrides to defaults.
  Future<void> resetToDefaults() async {
    _resetDefaults();
    await _persist();
    notifyListeners();
  }

  Future<void> setRoleEnabled(String roleId, bool enabled) async {
    if (enabled) {
      _disabledRoleIds.remove(roleId);
    } else {
      _disabledRoleIds.add(roleId);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setOverride(AgentRoleOverride? override) async {
    if (override == null || override.roleId.isEmpty) return;
    if (!override.hasModelOverride) {
      _overrides.remove(override.roleId);
    } else {
      _overrides[override.roleId] = override;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setAutopilot({
    required bool enabled,
    String? exchangeId,
    bool clearExchangeId = false,
    double? maxNotional,
    bool clearMaxNotional = false,
    int? maxOpenProposals,
  }) async {
    _autopilotEnabled = enabled;
    if (clearExchangeId) {
      _autopilotExchangeId = null;
    } else if (exchangeId != null) {
      _autopilotExchangeId = exchangeId;
    }
    if (clearMaxNotional) {
      _autopilotMaxNotional = null;
    } else if (maxNotional != null) {
      _autopilotMaxNotional = maxNotional;
    }
    if (maxOpenProposals != null) {
      _autopilotMaxOpenProposals = maxOpenProposals;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setSchedule({
    required bool enabled,
    AgentScheduleInterval? interval,
    List<String>? symbols,
    bool? useInvestInterest,
  }) async {
    _scheduleEnabled = enabled;
    if (interval != null) _scheduleInterval = interval;
    if (symbols != null) {
      _scheduleSymbols = normalizeScheduleSymbols(symbols);
    }
    if (useInvestInterest != null) {
      _scheduleUseInvestInterest = useInvestInterest;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> updateScheduleLastRunAt(DateTime at) async {
    _scheduleLastRunAt = at.toUtc();
    await _persist();
    notifyListeners();
  }

  Future<void> setAnswerMood(AgentAnswerMood mood) async {
    _answerMood = mood;
    await _persist();
    notifyListeners();
  }

  Future<void> setAnswerMoodNote(String? note) async {
    _answerMoodNote = normalizeAnswerMoodNote(note);
    await _persist();
    notifyListeners();
  }

  /// Promote Autopilot/Schedule from legacy per-role connections (once).
  Future<void> migrateFromConnections(
    Iterable<AgentConnection> connections,
  ) async {
    final slice = store?.getSlice(UserConfigKeys.agentApp);
    if (slice is Map && slice.isNotEmpty) return;

    AgentConnection? trading;
    AgentConnection? scheduled;
    for (final c in connections) {
      if (c.connected && c.autopilotEnabled) trading ??= c;
      if (c.connected && c.scheduleEnabled) scheduled ??= c;
    }
    if (trading == null && scheduled == null) return;

    if (trading != null) {
      _autopilotEnabled = true;
      _autopilotExchangeId = trading.autopilotExchangeId;
      _autopilotMaxNotional = trading.autopilotMaxNotional;
      _autopilotMaxOpenProposals = trading.autopilotMaxOpenProposals;
    }
    if (scheduled != null) {
      _scheduleEnabled = true;
      _scheduleInterval = scheduled.scheduleInterval;
      _scheduleSymbols = List<String>.from(scheduled.scheduleSymbols);
      _scheduleUseInvestInterest = scheduled.scheduleUseInvestInterest;
      _scheduleLastRunAt = scheduled.scheduleLastRunAt;
    }
    await _persist();
    notifyListeners();
  }
}
