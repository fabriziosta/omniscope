import 'package:flutter/foundation.dart';

import 'config_list_slice.dart';
import 'user_config_store.dart';

/// Shared load / upsert / delete / clear for capped list slices in config.
abstract class ConfigListRepository<T> extends ChangeNotifier {
  ConfigListRepository({
    this.store,
    required this.sliceKey,
    required this.listKey,
    required this.maxStored,
    required this.idOf,
    required this.fromJson,
    required this.toJson,
  });

  UserConfigStore? store;
  final String sliceKey;
  final String listKey;
  final int maxStored;
  final String Function(T item) idOf;
  final T? Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;

  List<T> _items = const [];
  bool _ready = false;

  bool get isReady => _ready;
  List<T> get items => List.unmodifiable(_items);

  @protected
  List<T> get mutableItems => _items;

  @protected
  set mutableItems(List<T> value) => _items = value;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(sliceKey);
    _items = ConfigListSlice.parseItems(slice, listKey, fromJson);
    _ready = true;
    notifyListeners();
  }

  Future<void> upsert(T item) async {
    _items = ConfigListSlice.prependCapped(
      _items,
      item,
      maxStored: maxStored,
      exclude: (existing) => idOf(existing) == idOf(item),
    );
    await persistItems();
    notifyListeners();
  }

  Future<bool> delete(String id) async {
    final before = _items.length;
    _items = [
      for (final item in _items)
        if (idOf(item) != id) item,
    ];
    if (_items.length == before) return false;
    await persistItems();
    notifyListeners();
    return true;
  }

  Future<void> clearAll() async {
    _items = const [];
    await persistItems();
    notifyListeners();
  }

  @protected
  Future<void> persistItems() async {
    await ConfigListSlice.persist(
      store,
      sliceKey: sliceKey,
      listKey: listKey,
      items: _items,
      toJson: toJson,
    );
  }
}
