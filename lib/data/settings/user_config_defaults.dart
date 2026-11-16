import '../../core/brand_colors.dart';
import '../portfolio/models.dart';
import 'user_config_keys.dart';

/// Canonical default shapes for every [UserConfigStore] slice.
///
/// Used when creating `omniscope.json` and when backfilling keys added by new
/// features. User-provided values always win; only missing (or null) keys are
/// filled. When adding a field or slice, update the matching entry here so
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

  static final Map<String, dynamic> _document = {
    UserConfigKeys.version: UserConfigKeys.currentVersion,
    UserConfigKeys.theme: {
      'mode': 'system',
      'palette': BrandColors.defaultPaletteId,
    },
    UserConfigKeys.display: {
      'listDensity': 'comfortable',
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
    },
    UserConfigKeys.agentChats: {
      'threads': <dynamic>[],
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
    },
    UserConfigKeys.mandate: {
      'goal': 'learn',
      'horizon': 'medium',
      'universe': 'both',
      'maxSymbolCount': 20,
      'maxOpenProposals': 3,
      'cadencePreference': 'hour1',
    },
  };

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
