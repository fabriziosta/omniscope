import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Persisted appearance preference for [ShadApp.themeMode].
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({this.store});

  UserConfigStore? store;
  ThemeMode _mode = ThemeMode.system;
  bool _ready = false;

  ThemeMode get mode => _mode;
  bool get isReady => _ready;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final raw = this.store?.getSlice(UserConfigKeys.theme);
    _mode = _parse(raw is String ? raw : null) ?? ThemeMode.system;
    _ready = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await store?.setSlice(UserConfigKeys.theme, _encode(mode));
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode? _parse(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }
}
