import '../../core/brand_colors.dart';
import '../agents/models.dart';
import '../portfolio/models.dart';
import 'user_config_keys.dart';

/// Canonical default shapes for every [UserConfigStore] slice.
///
/// Used when creating `omniscope.json` and when backfilling keys added by new
/// features. On load / Import, missing keys are filled and invalid values
/// (wrong type or unknown enum) are overwritten with the default and written
/// back. When adding a field or slice, update the matching entry here so
/// existing configs pick it up on the next load.
abstract final class UserConfigDefaults {
  static Map<String, dynamic> document() => _deepCopy(_document);

  /// Deep-merge [defaults] under [target]. Existing non-null values win.
  /// Nested maps are merged; lists and scalars are replaced only when missing.
  /// Returns true if any key was added.
  static bool mergeInto(
    Map<String, dynamic> target, [
    Map<String, dynamic>? defaults,
  ]) {
    final source = defaults ?? _document;
    var changed = false;
    for (final entry in source.entries) {
      final key = entry.key;
      final def = entry.value;
      final existing = target[key];
      if (existing == null) {
        target[key] = _cloneValue(def);
        changed = true;
        continue;
      }
      if (existing is Map && def is Map) {
        final child = existing is Map<String, dynamic>
            ? existing
            : Map<String, dynamic>.from(existing);
        if (!identical(child, existing)) {
          target[key] = child;
        }
        if (mergeInto(child, Map<String, dynamic>.from(def))) {
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Replace wrong-typed or unknown enum values with defaults.
  ///
  /// Call after [mergeInto]. Returns true if any value was overwritten.
  static bool sanitizeInto(Map<String, dynamic> target) {
    var changed = false;

    // Legacy theme was a bare mode string — keep valid ones; reset junk.
    final theme = target[UserConfigKeys.theme];
    if (theme is String) {
      if (!_themeModes.contains(theme)) {
        target[UserConfigKeys.theme] = _cloneValue(_document[UserConfigKeys.theme]);
        changed = true;
      }
    }

    if (_sanitizeTree(target, _document, _enumAllowlists)) {
      changed = true;
    }

    return changed;
  }

  static final Map<String, dynamic> _document = {
    UserConfigKeys.version: UserConfigKeys.currentVersion,
    UserConfigKeys.theme: {
      'mode': 'system',
      'palette': BrandColors.defaultPaletteId,
    },
    UserConfigKeys.display: {
      'listDensity': 'compact',
      'priceFormat': 'full',
      'defaultChartRange': '1mo',
    },
    UserConfigKeys.dataSources: {
      'disabledMarkets': <String>[],
      'disabledCrypto': <String>[],
      'disabledBrokers': <String>[],
    },
    UserConfigKeys.secrets: <String, dynamic>{},
    UserConfigKeys.agents: {
      'connections': <dynamic>[],
    },
    UserConfigKeys.llmRuntime: {
      'providers': <dynamic>[],
    },
    UserConfigKeys.agentApp: {
      'disabledRoleIds': <String>[],
      'overrides': <dynamic>[],
      'autopilotEnabled': false,
      'autopilotMaxOpenProposals': 3,
      'scheduleEnabled': false,
      'scheduleInterval': 'hour1',
      'scheduleSymbols': <String>[],
      'scheduleUseInvestInterest': true,
      'answerMood': 'plain',
      // scheduleChatId omitted until Schedule is enabled (null = no linked chat).
    },
    UserConfigKeys.agentChats: {
      'threads': <dynamic>[],
    },
    UserConfigKeys.agentMemory: {
      'facts': <dynamic>[],
    },
    UserConfigKeys.tradeProposals: {
      'proposals': <dynamic>[],
    },
    UserConfigKeys.investInterestProposals: {
      'proposals': <dynamic>[],
    },
    UserConfigKeys.agentActivity: {
      'events': <dynamic>[],
    },
    UserConfigKeys.notifications: {
      'items': <dynamic>[],
    },
    UserConfigKeys.paperPortfolio: {
      'cash': PortfolioState.defaultStartingCash,
      'holdings': <dynamic>[],
      'startingCash': PortfolioState.defaultStartingCash,
    },
    UserConfigKeys.favorites: {
      'symbols': <String>[],
      'investInterest': <String>[],
      'investInterestProvenance': <String, dynamic>{},
    },
    UserConfigKeys.mandate: {
      'goal': 'learn',
      'horizon': 'medium',
      'universe': 'both',
      'maxSymbolCount': 20,
      'maxOpenProposals': 3,
      'maxAutopilotFillsPerDay': 10,
      'cadencePreference': 'hour1',
    },
  };

  static final Set<String> _themeModes = {'light', 'dark', 'system'};

  static final Set<String> _paletteIds = {
    for (final p in BrandColors.all) p.id,
  };

  static final Set<String> _scheduleIntervals = {
    for (final e in AgentScheduleInterval.values) e.name,
  };

  static final Set<String> _answerMoods = {
    for (final e in AgentAnswerMood.values) e.name,
  };

  /// Nested allowlists parallel to [_document] string enum fields.
  ///
  /// Leaf values are [Set<String>] of allowed tokens; intermediate nodes are
  /// maps keyed like the config document.
  static final Map<String, dynamic> _enumAllowlists = {
    UserConfigKeys.theme: <String, dynamic>{
      'mode': _themeModes,
      'palette': _paletteIds,
    },
    UserConfigKeys.display: <String, dynamic>{
      // Keep in sync with ListDensity / PriceFormat / ChartRangePreset.
      'listDensity': {'comfortable', 'compact'},
      'priceFormat': {'full', 'compact'},
      'defaultChartRange': {'1mo', '3mo', '1y'},
    },
    UserConfigKeys.agentApp: <String, dynamic>{
      'scheduleInterval': _scheduleIntervals,
      'answerMood': _answerMoods,
    },
    UserConfigKeys.mandate: <String, dynamic>{
      // Keep in sync with MandateGoal / Horizon / Universe.
      'goal': {'learn', 'preserve', 'grow'},
      'horizon': {'short', 'medium', 'long'},
      'universe': {'equities', 'crypto', 'both'},
      'cadencePreference': _scheduleIntervals,
    },
  };

  /// Walk [target] alongside [defaults]; fix type mismatches and bad enums.
  static bool _sanitizeTree(
    Map<String, dynamic> target,
    Map<String, dynamic> defaults,
    Map<String, dynamic>? allowlists,
  ) {
    var changed = false;
    for (final entry in defaults.entries) {
      final key = entry.key;
      final def = entry.value;
      final existing = target[key];
      if (existing == null) continue;

      final childAllow = allowlists?[key];

      if (def is Map) {
        if (existing is! Map) {
          // Keep legacy bare theme mode strings (handled in [sanitizeInto]).
          if (key == UserConfigKeys.theme && existing is String) {
            continue;
          }
          target[key] = _cloneValue(def);
          changed = true;
          continue;
        }
        final child = existing is Map<String, dynamic>
            ? existing
            : Map<String, dynamic>.from(existing);
        if (!identical(child, existing)) {
          target[key] = child;
        }
        final nestedAllow = childAllow is Map
            ? Map<String, dynamic>.from(childAllow)
            : null;
        if (_sanitizeTree(
          child,
          Map<String, dynamic>.from(def),
          nestedAllow,
        )) {
          changed = true;
        }
        continue;
      }

      if (def is List) {
        if (existing is! List) {
          target[key] = _cloneValue(def);
          changed = true;
        }
        continue;
      }

      if (!_sameScalarType(existing, def)) {
        target[key] = _cloneValue(def);
        changed = true;
        continue;
      }

      if (def is String && existing is String) {
        if (childAllow is Set && !childAllow.contains(existing)) {
          target[key] = def;
          changed = true;
        }
      }
    }
    return changed;
  }

  static bool _sameScalarType(Object existing, Object def) {
    if (def is String) return existing is String;
    if (def is bool) return existing is bool;
    if (def is num) return existing is num;
    return existing.runtimeType == def.runtimeType;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      out[entry.key] = _cloneValue(entry.value);
    }
    return out;
  }

  static Object? _cloneValue(Object? value) {
    if (value is Map) {
      return _deepCopy(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return value;
  }
}
