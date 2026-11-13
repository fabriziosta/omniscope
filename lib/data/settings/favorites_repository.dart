import 'package:flutter/foundation.dart';

import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Starred Markets symbols (equities and spot crypto) in one ordered list.
class FavoritesRepository extends ChangeNotifier {
  FavoritesRepository({this.store});

  UserConfigStore? store;
  final List<String> _symbols = [];
  bool _ready = false;

  bool get isReady => _ready;

  List<String> get symbols => List.unmodifiable(_symbols);

  bool isFavorite(String symbol) {
    final key = symbol.trim();
    if (key.isEmpty) return false;
    return _symbols.contains(key);
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

  Future<void> clearAll() async {
    _symbols.clear();
    notifyListeners();
    await _persist();
  }

  /// Reorders favorites.
  ///
  /// [newIndex] is the destination after the item is removed (as reported by
  /// Flutter's [ReorderableListView.onReorderItem]).
  Future<void> reorderFavorites(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _symbols.length) return;
    if (newIndex < 0 || newIndex >= _symbols.length) return;
    if (newIndex == oldIndex) return;
    final item = _symbols.removeAt(oldIndex);
    _symbols.insert(newIndex, item);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.favorites, {
      'symbols': List<String>.from(_symbols),
    });
  }

  void _applySlice(Object? slice) {
    _symbols.clear();
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);

    final unified = map['symbols'];
    if (unified is List) {
      _appendUnique(unified);
      return;
    }

    // Legacy: { markets: [...], crypto: { exchangeId: [...] } }
    final markets = map['markets'];
    if (markets is List) {
      _appendUnique(markets);
    }
    final crypto = map['crypto'];
    if (crypto is Map) {
      final exchangeIds = crypto.keys.map((k) => k.toString()).toList()
        ..sort();
      for (final id in exchangeIds) {
        if (id.isEmpty) continue;
        final symbols = crypto[id];
        if (symbols is List) {
          _appendUnique(symbols);
        }
      }
    }
  }

  void _appendUnique(List<dynamic> items) {
    for (final item in items) {
      if (item is! String) continue;
      final key = item.trim();
      if (key.isEmpty || _symbols.contains(key)) continue;
      _symbols.add(key);
    }
  }
}
