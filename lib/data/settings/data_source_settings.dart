import 'package:flutter/foundation.dart';

import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Persisted enable/disable for equities providers and crypto venues.
///
/// Uses an opt-out model ([disabledMarketIds] / [disabledCryptoIds]) so newly
/// registered providers default to on when the catalog grows.
class DataSourceSettings extends ChangeNotifier {
  DataSourceSettings({this.store});

  UserConfigStore? store;
  final Set<String> _disabledMarketIds = {};
  final Set<String> _disabledCryptoIds = {};
  final Set<String> _disabledBrokerIds = {};
  bool _ready = false;

  bool get isReady => _ready;

  bool isMarketEnabled(String id) => !_disabledMarketIds.contains(id);

  bool isCryptoEnabled(String id) => !_disabledCryptoIds.contains(id);

  bool isBrokerEnabled(String id) => !_disabledBrokerIds.contains(id);

  Set<String> get disabledMarketIds => Set.unmodifiable(_disabledMarketIds);

  Set<String> get disabledCryptoIds => Set.unmodifiable(_disabledCryptoIds);

  Set<String> get disabledBrokerIds => Set.unmodifiable(_disabledBrokerIds);

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.dataSources);
    _disabledMarketIds
      ..clear()
      ..addAll(_parseIdList(slice, 'disabledMarkets'));
    _disabledCryptoIds
      ..clear()
      ..addAll(_parseIdList(slice, 'disabledCrypto'));
    _disabledBrokerIds
      ..clear()
      ..addAll(_parseIdList(slice, 'disabledBrokers'));
    _ready = true;
    notifyListeners();
  }

  Future<void> setMarketEnabled(String id, bool enabled) async {
    if (isMarketEnabled(id) == enabled) return;
    if (enabled) {
      _disabledMarketIds.remove(id);
    } else {
      _disabledMarketIds.add(id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setCryptoEnabled(String id, bool enabled) async {
    if (isCryptoEnabled(id) == enabled) return;
    if (enabled) {
      _disabledCryptoIds.remove(id);
    } else {
      _disabledCryptoIds.add(id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setBrokerEnabled(String id, bool enabled) async {
    if (isBrokerEnabled(id) == enabled) return;
    if (enabled) {
      _disabledBrokerIds.remove(id);
    } else {
      _disabledBrokerIds.add(id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final markets = _disabledMarketIds.toList(growable: false)..sort();
    final crypto = _disabledCryptoIds.toList(growable: false)..sort();
    final brokers = _disabledBrokerIds.toList(growable: false)..sort();
    await store?.setSlice(UserConfigKeys.dataSources, {
      'disabledMarkets': markets,
      'disabledCrypto': crypto,
      'disabledBrokers': brokers,
    });
  }

  static Set<String> _parseIdList(Object? slice, String key) {
    if (slice is! Map) return {};
    final list = Map<String, dynamic>.from(slice)[key];
    if (list is! List) return {};
    return {
      for (final item in list)
        if (item is String && item.isNotEmpty) item,
    };
  }
}
