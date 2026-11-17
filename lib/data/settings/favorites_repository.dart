import 'package:flutter/foundation.dart';

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
  DateTime? _investInterestManagedAt;
  String? _investInterestManagedByRoleId;
  bool _ready = false;

  bool get isReady => _ready;

  List<String> get symbols => List.unmodifiable(_symbols);

  List<String> get investInterestSymbols =>
      List.unmodifiable(_investInterest);

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
    } else {
      _investInterest.add(key);
    }
    _clearInvestInterestManaged();
    notifyListeners();
    await _persist();
  }

  /// Replace Invest interest (Confirm path for agent proposals).
  Future<void> applyInvestInterest(
    List<String> symbols, {
    String? managedByRoleId,
  }) async {
    _investInterest
      ..clear()
      ..addAll(_uniqueSymbols(symbols));
    if (managedByRoleId != null && managedByRoleId.trim().isNotEmpty) {
      _investInterestManagedAt = DateTime.now().toUtc();
      _investInterestManagedByRoleId = managedByRoleId.trim();
    } else {
      _clearInvestInterestManaged();
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
    _clearInvestInterestManaged();
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
    _clearInvestInterestManaged();
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);

    final invest = map['investInterest'];
    if (invest is List) {
      _appendUniqueTo(_investInterest, invest);
    }
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
