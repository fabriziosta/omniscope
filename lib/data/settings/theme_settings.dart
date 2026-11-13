import 'package:flutter/foundation.dart';
import '../../core/material_compat.dart' show ThemeMode;

import '../../core/brand_colors.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// Persisted appearance preference for [ShadApp.themeMode] and brand palette.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({this.store});

  UserConfigStore? store;
  ThemeMode _mode = ThemeMode.system;
  String _paletteId = BrandColors.defaultPaletteId;
  bool _ready = false;

  ThemeMode get mode => _mode;
  String get paletteId => _paletteId;
  BrandPalette get palette => BrandColors.palette(_paletteId);
  bool get isReady => _ready;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final raw = this.store?.getSlice(UserConfigKeys.theme);
    if (raw is String) {
      // Legacy: theme slice was a bare mode string.
      _mode = _parseMode(raw) ?? ThemeMode.system;
      _paletteId = BrandColors.defaultPaletteId;
    } else if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      _mode = _parseMode(map['mode'] as String?) ?? ThemeMode.system;
      _paletteId = BrandColors.palette(map['palette'] as String?).id;
    } else {
      _mode = ThemeMode.system;
      _paletteId = BrandColors.defaultPaletteId;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setPaletteId(String id) async {
    final next = BrandColors.palette(id).id;
    if (_paletteId == next) return;
    _paletteId = next;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.theme, {
      'mode': _encodeMode(_mode),
      'palette': _paletteId,
    });
  }

  static String _encodeMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode? _parseMode(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }
}
