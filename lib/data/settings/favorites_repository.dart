import 'package:flutter/foundation.dart';

import 'invest_interest_provenance.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Starred Markets symbols and a separate agent-facing invest-interest list.
///
/// Favorites and invest interest are independent ordered lists (a symbol may
/// be in both or either). Persisted under the shared `favorites` config slice.
class FavoritesRepository extends ChangeNotifier {
  FavoritesRepository({this.store});

  UserConfigStore? store;
  final List<String> _symbols = [];
  final List<String> _investInterest = [];
  final Map<String, InvestInterestProvenance> _investInterestProvenance = {};
  DateTime? _investInterestManagedAt;
  String? _investInterestManagedByRoleId;
  bool _ready = false;

  bool get isReady => _ready;

  List<String> get symbols => List.unmodifiable(_symbols);

  List<String> get investInterestSymbols =>
      List.unmodifiable(_investInterest);

  /// Per-symbol You/Agent provenance (missing key → treat as You).
  Map<String, InvestInterestProvenance> get investInterestProvenance =>
      Map.unmodifiable(_investInterestProvenance);

  /// When the last confirmed agent proposal applied the invest-interest list.
  DateTime? get investInterestManagedAt => _investInterestManagedAt;

  String? get investInterestManagedByRoleId =>
      _investInterestManagedByRoleId;

  /// True when Invest interest was last written by a confirmed agent proposal
  /// and the user has not manually edited it since.
  bool get investInterestManagedByAgent =>
      _investInterestManagedAt != null;

  bool isFavorite(String symbol) {
    final key = symbol.trim();
    if (key.isEmpty) return false;
    return _symbols.contains(key);
  }

  bool isInvestInterest(String symbol) {
    final key = symbol.trim();
    if (key.isEmpty) return false;
    return _investInterest.contains(key);
  }

  /// Provenance for [symbol]; missing → [InvestInterestSource.user].
  InvestInterestProvenance provenanceFor(String symbol) {
    final key = symbol.trim();
    return _investInterestProvenance[key] ?? InvestInterestProvenance.user();
  }

  /// Source label for UI chips (`You` / `Agent`).
  InvestInterestSource sourceFor(String symbol) =>
      provenanceFor(symbol).source;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _applySlice(this.store?.getSlice(UserConfigKeys.favorites));
    _ready = true;
    notifyListeners();
  }

  Future<void> toggleFavorite(String symbol) async {
    final key = symbol.trim();
    if (key.isEmpty) return;
    if (_symbols.contains(key)) {
      _symbols.remove(key);
    } else {
      _symbols.add(key);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> toggleInvestInterest(String symbol) async {
    final key = symbol.trim();
    if (key.isEmpty) return;
    if (_investInterest.contains(key)) {
      _investInterest.remove(key);
      _investInterestProvenance.remove(key);
    } else {
      _investInterest.add(key);
      _investInterestProvenance[key] = InvestInterestProvenance.user();
    }
    _clearInvestInterestManaged();
    notifyListeners();
    await _persist();
  }

  /// Replace Invest interest (Confirm path for agent set / full resolve).
  ///
  /// When [managedByRoleId] is set, every symbol in [symbols] is marked
  /// agent-sourced. Symbols removed from the list drop provenance.
  Future<void> applyInvestInterest(
    List<String> symbols, {
    String? managedByRoleId,
  }) async {
    final next = _uniqueSymbols(symbols);
    final roleId = managedByRoleId?.trim();
    final agentManaged = roleId != null && roleId.isNotEmpty;
    final now = DateTime.now().toUtc();

    _investInterest
      ..clear()
      ..addAll(next);

    final keep = <String, InvestInterestProvenance>{};
    for (final symbol in next) {
      if (agentManaged) {
        keep[symbol] = InvestInterestProvenance.agent(
          roleId: roleId,
          addedAt: now,
        );
      } else {
        keep[symbol] = _investInterestProvenance[symbol] ??
            InvestInterestProvenance.user();
      }
    }
    _investInterestProvenance
      ..clear()
      ..addAll(keep);

    if (agentManaged) {
      _investInterestManagedAt = now;
      _investInterestManagedByRoleId = roleId;
    } else {
      _clearInvestInterestManaged();
    }
    notifyListeners();
    await _persist();
  }

  /// Append agent-proposed symbols without wiping existing provenance.
  ///
  /// Used by Autopilot add-only and Confirm when applying add/remove diffs.
  /// [remove] drops those symbols (case-insensitive); [add] appends (deduped)
  /// and marks them agent-sourced when [managedByRoleId] is set.
  Future<void> applyInvestInterestDiff({
    List<String> add = const [],
    List<String> remove = const [],
    String? managedByRoleId,
  }) async {
    final roleId = managedByRoleId?.trim();
    final agentManaged = roleId != null && roleId.isNotEmpty;
    final now = DateTime.now().toUtc();

    final removeUpper = {
      for (final s in remove)
        if (s.trim().isNotEmpty) s.trim().toUpperCase(),
    };
    if (removeUpper.isNotEmpty) {
      final dropped = <String>[];
      _investInterest.removeWhere((symbol) {
        if (removeUpper.contains(symbol.trim().toUpperCase())) {
          dropped.add(symbol);
          return true;
        }
        return false;
      });
      for (final key in dropped) {
        _investInterestProvenance.remove(key);
      }
    }

    final seenUpper = {
      for (final s in _investInterest) s.trim().toUpperCase(),
    };
    var addedAny = false;
    for (final raw in add) {
      final key = raw.trim();
      if (key.isEmpty) continue;
      final upper = key.toUpperCase();
      if (seenUpper.contains(upper)) continue;
      _investInterest.add(key);
      seenUpper.add(upper);
      addedAny = true;
      _investInterestProvenance[key] = agentManaged
          ? InvestInterestProvenance.agent(roleId: roleId, addedAt: now)
          : InvestInterestProvenance.user();
    }

    if (agentManaged && (addedAny || removeUpper.isNotEmpty)) {
      _investInterestManagedAt = now;
      _investInterestManagedByRoleId = roleId;
    }
    notifyListeners();
    await _persist();
  }

  /// Clears favorites only; invest interest is unchanged.
  Future<void> clearAll() async {
    _symbols.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> clearInvestInterest() async {
    _investInterest.clear();
    _investInterestProvenance.clear();
    _clearInvestInterestManaged();
    notifyListeners();
    await _persist();
  }

  /// Reorders favorites.
  ///
  /// [newIndex] is the destination after the item is removed (as reported by
  /// Flutter's [ReorderableListView.onReorderItem]).
  Future<void> reorderFavorites(int oldIndex, int newIndex) async {
    if (!_reorderInPlace(_symbols, oldIndex, newIndex)) return;
    notifyListeners();
    await _persist();
  }

  /// Reorders invest interest.
  ///
  /// [newIndex] is the destination after the item is removed (as reported by
  /// Flutter's [ReorderableListView.onReorderItem]).
  Future<void> reorderInvestInterest(int oldIndex, int newIndex) async {
    if (!_reorderInPlace(_investInterest, oldIndex, newIndex)) return;
    // Reorder alone does not change who added each symbol.
    notifyListeners();
    await _persist();
  }

  bool _reorderInPlace(List<String> list, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= list.length) return false;
    if (newIndex < 0 || newIndex >= list.length) return false;
    if (newIndex == oldIndex) return false;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    return true;
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.favorites, {
      'symbols': List<String>.from(_symbols),
      'investInterest': List<String>.from(_investInterest),
      'investInterestProvenance': {
        for (final e in _investInterestProvenance.entries)
          e.key: e.value.toJson(),
      },
      if (_investInterestManagedAt != null)
        'investInterestManagedAt':
            _investInterestManagedAt!.toIso8601String(),
      if (_investInterestManagedByRoleId != null)
        'investInterestManagedByRoleId': _investInterestManagedByRoleId,
    });
  }

  void _applySlice(Object? slice) {
    _symbols.clear();
    _investInterest.clear();
    _investInterestProvenance.clear();
    _clearInvestInterestManaged();
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);

    final invest = map['investInterest'];
    if (invest is List) {
      _appendUniqueTo(_investInterest, invest);
    }
    final provenanceRaw = map['investInterestProvenance'];
    if (provenanceRaw is Map) {
      for (final entry in provenanceRaw.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final value = entry.value;
        if (value is Map) {
          _investInterestProvenance[key] = InvestInterestProvenance.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      }
    }
    // Drop provenance for symbols no longer on the list.
    _investInterestProvenance
        .removeWhere((key, _) => !_investInterest.contains(key));

    final managedAtRaw = map['investInterestManagedAt'];
    final managedAt = DateTime.tryParse(
      managedAtRaw is String ? managedAtRaw : '',
    );
    final managedByRaw = map['investInterestManagedByRoleId'];
    final managedBy = managedByRaw is String ? managedByRaw : null;
    if (managedAt != null) {
      _investInterestManagedAt = managedAt.toUtc();
      _investInterestManagedByRoleId =
          managedBy?.trim().isNotEmpty == true ? managedBy!.trim() : null;
    }

    final unified = map['symbols'];
    if (unified is List) {
      _appendUniqueTo(_symbols, unified);
    }

    // Legacy: { markets: [...], crypto: { exchangeId: [...] } }.
    // Also used when defaults backfilled an empty `symbols` list over a
    // still-present legacy shape (Import / older files).
    if (_symbols.isEmpty) {
      final markets = map['markets'];
      if (markets is List) {
        _appendUniqueTo(_symbols, markets);
      }
      final crypto = map['crypto'];
      if (crypto is Map) {
        final exchangeIds = crypto.keys.map((k) => k.toString()).toList()
          ..sort();
        for (final id in exchangeIds) {
          if (id.isEmpty) continue;
          final symbols = crypto[id];
          if (symbols is List) {
            _appendUniqueTo(_symbols, symbols);
          }
        }
      }
    }
  }

  void _appendUniqueTo(List<String> target, List<dynamic> items) {
    for (final item in items) {
      if (item is! String) continue;
      final key = item.trim();
      if (key.isEmpty || target.contains(key)) continue;
      target.add(key);
    }
  }

  List<String> _uniqueSymbols(List<String> symbols) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in symbols) {
      final key = raw.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(key);
    }
    return out;
  }

  void _clearInvestInterestManaged() {
    _investInterestManagedAt = null;
    _investInterestManagedByRoleId = null;
  }
}
