import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/user_config_file.dart';
import 'user_config_keys.dart';

/// Single JSON document for secrets, favorites, and all app customizations.
///
/// Native: `{appSupport}/omniscope.json` by default; desktop may override the
/// path via prefs [UserConfigKeys.pathOverridePrefsKey].
/// Web: full document in prefs [UserConfigKeys.webBlobPrefsKey].
class UserConfigStore extends ChangeNotifier {
  UserConfigStore({
    SharedPreferences? prefs,
    this.memoryOnly = false,
    Map<String, dynamic>? initialDocument,
  })  : _prefsOverride = prefs,
        _document = initialDocument != null
            ? _deepCopyMap(initialDocument)
            : _emptyDocument();

  final SharedPreferences? _prefsOverride;

  /// When true, never touch the filesystem (tests / in-memory).
  final bool memoryOnly;

  Map<String, dynamic> _document;
  String? _resolvedPath;
  String? _pathOverride;
  String? _defaultPath;
  bool _ready = false;
  bool _usesFilesystem = false;

  bool get isReady => _ready;

  /// Absolute path when using a file; null on Web / memory-only.
  String? get effectivePath => _usesFilesystem ? _resolvedPath : null;

  /// Platform default path (even if a custom override is active).
  String? get defaultPath => _defaultPath;

  /// Active custom path override from prefs, if any.
  String? get pathOverride => _pathOverride;

  bool get usesFilesystem => _usesFilesystem;

  /// Desktop (Linux / Windows / macOS) can pick a custom file location.
  bool get supportsCustomPath {
    if (memoryOnly || kIsWeb || !UserConfigFile.supportsFilesystem) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }

  /// Pretty-printed JSON of the current document.
  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(_document);

  Object? getSlice(String key) => _document[key];

  Map<String, dynamic> get document =>
      Map<String, dynamic>.unmodifiable(_document);

  Future<void> load() async {
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    _pathOverride = prefs.getString(UserConfigKeys.pathOverridePrefsKey);
    if (_pathOverride != null && _pathOverride!.trim().isEmpty) {
      _pathOverride = null;
    }

    if (!memoryOnly && UserConfigFile.supportsFilesystem) {
      _defaultPath = await UserConfigFile.defaultPath();
    } else {
      _defaultPath = null;
    }

    _usesFilesystem = !memoryOnly &&
        UserConfigFile.supportsFilesystem &&
        (_pathOverride != null || _defaultPath != null);
    _resolvedPath = _usesFilesystem
        ? (_pathOverride?.trim().isNotEmpty == true
            ? _pathOverride!.trim()
            : _defaultPath)
        : null;

    Map<String, dynamic>? loaded;
    if (_usesFilesystem && _resolvedPath != null) {
      final raw = await UserConfigFile.read(_resolvedPath!);
      loaded = _tryParseDocument(raw);
    } else if (!memoryOnly) {
      loaded = _tryParseDocument(prefs.getString(UserConfigKeys.webBlobPrefsKey));
    }

    if (loaded == null || loaded.isEmpty) {
      _document = _emptyDocument();
      final migrated = await _migrateLegacy(prefs);
      if (migrated) {
        await _persistImmediate();
        await _clearLegacy(prefs);
      }
    } else {
      _document = loaded;
      if (_document[UserConfigKeys.version] is! int) {
        _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
      }
      // Absorb any leftover legacy keys once, then drop them.
      final migrated = await _migrateLegacy(prefs);
      if (migrated) {
        await _persistImmediate();
        await _clearLegacy(prefs);
      }
    }

    _ready = true;
    notifyListeners();
  }

  /// Replace one top-level slice and persist.
  Future<void> setSlice(String key, Object? value) async {
    if (value == null) {
      _document.remove(key);
    } else {
      _document[key] = value is Map
          ? _deepCopyMap(Map<String, dynamic>.from(value))
          : value;
    }
    notifyListeners();
    await _persistImmediate();
  }

  /// Mutate the document in place, then persist.
  Future<void> update(void Function(Map<String, dynamic> doc) mutate) async {
    mutate(_document);
    notifyListeners();
    await _persistImmediate();
  }

  /// Replace the whole document from Import (JSON text).
  Future<void> importJson(String raw) async {
    final parsed = _tryParseDocument(raw);
    if (parsed == null) {
      throw const FormatException('Invalid Omniscope config JSON.');
    }
    _document = parsed;
    if (_document[UserConfigKeys.version] is! int) {
      _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
    }
    await _persistImmediate();
    notifyListeners();
  }

  /// Set or clear a custom config path (desktop). Copies the current document
  /// to the new location when [copyExisting] is true.
  Future<void> setCustomPath(
    String? path, {
    bool copyExisting = true,
  }) async {
    if (!supportsCustomPath) return;

    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    final trimmed = path?.trim();
    final nextOverride =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    if (copyExisting &&
        _usesFilesystem &&
        _resolvedPath != null &&
        nextOverride != null &&
        nextOverride != _resolvedPath) {
      await UserConfigFile.write(nextOverride, exportJson());
    }

    _pathOverride = nextOverride;
    if (nextOverride == null) {
      await prefs.remove(UserConfigKeys.pathOverridePrefsKey);
    } else {
      await prefs.setString(UserConfigKeys.pathOverridePrefsKey, nextOverride);
    }

    // Reload against the new location (or default).
    _ready = false;
    await load();
    // Ensure the document is present at the resolved path.
    await _persistImmediate();
    notifyListeners();
  }

  Future<void> _persistImmediate() async {
    _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
    final encoded = jsonEncode(_document);

    if (memoryOnly) return;

    if (_usesFilesystem && _resolvedPath != null) {
      await UserConfigFile.write(_resolvedPath!, encoded);
      return;
    }

    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.setString(UserConfigKeys.webBlobPrefsKey, encoded);
  }

  Future<bool> _migrateLegacy(SharedPreferences prefs) async {
    var changed = false;

    void takeStringSlice(String legacyKey, String sliceKey) {
      final raw = prefs.getString(legacyKey);
      if (raw == null || raw.isEmpty) return;
      if (_document.containsKey(sliceKey) && _document[sliceKey] != null) {
        // Prefer existing document value; still clear legacy later.
        return;
      }
      // Theme is a plain string; others are JSON objects (or legacy density).
      if (sliceKey == UserConfigKeys.theme) {
        _document[sliceKey] = raw;
        changed = true;
        return;
      }
      try {
        final decoded = jsonDecode(raw);
        _document[sliceKey] = decoded;
        changed = true;
      } catch (_) {
        if (sliceKey == UserConfigKeys.display) {
          // Legacy plain density string.
          _document[sliceKey] = {
            'listDensity': raw,
            'priceFormat': 'full',
            'defaultChartRange': '1mo',
          };
          changed = true;
        }
      }
    }

    takeStringSlice(UserConfigKeys.legacyTheme, UserConfigKeys.theme);
    takeStringSlice(UserConfigKeys.legacyDisplay, UserConfigKeys.display);
    takeStringSlice(
      UserConfigKeys.legacyDataSources,
      UserConfigKeys.dataSources,
    );
    takeStringSlice(UserConfigKeys.legacySecrets, UserConfigKeys.secrets);
    takeStringSlice(UserConfigKeys.legacyAgents, UserConfigKeys.agents);
    takeStringSlice(
      UserConfigKeys.legacyAgentChats,
      UserConfigKeys.agentChats,
    );
    takeStringSlice(
      UserConfigKeys.legacyPaperPortfolio,
      UserConfigKeys.paperPortfolio,
    );

    return changed;
  }

  Future<void> _clearLegacy(SharedPreferences prefs) async {
    for (final key in UserConfigKeys.legacyPrefsKeys) {
      await prefs.remove(key);
    }
  }

  static Map<String, dynamic> _emptyDocument() => {
        UserConfigKeys.version: UserConfigKeys.currentVersion,
      };

  static Map<String, dynamic>? _tryParseDocument(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _deepCopyMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map) {
        out[entry.key] =
            _deepCopyMap(Map<String, dynamic>.from(value));
      } else if (value is List) {
        out[entry.key] = List<dynamic>.from(value);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

}
