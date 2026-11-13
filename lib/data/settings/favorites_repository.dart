import 'package:flutter/foundation.dart';

import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Starred Markets symbols and per-exchange Crypto pairs.
class FavoritesRepository extends ChangeNotifier {
  FavoritesRepository({this.store});

  UserConfigStore? store;
  final List<String> _markets = [];
  final Map<String, List<String>> _crypto = {};
  bool _ready = false;

  bool get isReady => _ready;

  List<String> get marketSymbols => List.unmodifiable(_markets);

  List<String> cryptoSymbolsFor(String exchangeId) =>
      List.unmodifiable(_crypto[exchangeId] ?? const []);

  bool isMarketFavorite(String symbol) {
    final key = symbol.trim();
    if (key.isEmpty) return false;
    return _markets.contains(key);
  }

  bool isCryptoFavorite(String exchangeId, String symbol) {
    final key = symbol.trim();
    if (exchangeId.isEmpty || key.isEmpty) return false;
    return (_crypto[exchangeId] ?? const []).contains(key);
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _applySlice(this.store?.getSlice(UserConfigKeys.favorites));
    _ready = true;
    notifyListeners();
  }

  Future<void> toggleMarketFavorite(String symbol) async {
    final key = symbol.trim();
    if (key.isEmpty) return;
    if (_markets.contains(key)) {
      _markets.remove(key);
    } else {
      _markets.add(key);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> toggleCryptoFavorite(String exchangeId, String symbol) async {
    final key = symbol.trim();
    if (exchangeId.isEmpty || key.isEmpty) return;
    final list = _crypto.putIfAbsent(exchangeId, () => <String>[]);
    if (list.contains(key)) {
      list.remove(key);
    } else {
      list.add(key);
    }
    if (list.isEmpty) {
      _crypto.remove(exchangeId);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    _markets.clear();
    _crypto.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final cryptoOut = <String, List<String>>{};
    final exchangeIds = _crypto.keys.toList()..sort();
    for (final id in exchangeIds) {
      cryptoOut[id] = List<String>.from(_crypto[id]!);
    }
    await store?.setSlice(UserConfigKeys.favorites, {
      'markets': List<String>.from(_markets),
      'crypto': cryptoOut,
    });
  }

  void _applySlice(Object? slice) {
    _markets.clear();
    _crypto.clear();
    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);
    final markets = map['markets'];
    if (markets is List) {
      for (final item in markets) {
        if (item is String && item.trim().isNotEmpty) {
          _markets.add(item.trim());
        }
      }
    }
    final crypto = map['crypto'];
    if (crypto is Map) {
      for (final entry in crypto.entries) {
        final id = entry.key.toString();
        if (id.isEmpty) continue;
        final symbols = entry.value;
        if (symbols is! List) continue;
        final list = <String>[
          for (final item in symbols)
            if (item is String && item.trim().isNotEmpty) item.trim(),
        ];
        if (list.isNotEmpty) {
          _crypto[id] = list;
        }
      }
    }
  }
}
