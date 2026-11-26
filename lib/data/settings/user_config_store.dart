import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/user_config_file.dart';
import 'user_config_defaults.dart';
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
    Duration? persistDebounce,
  })  : _prefsOverride = prefs,
        _persistDebounce = persistDebounce ??
            (memoryOnly
                ? Duration.zero
                : const Duration(milliseconds: 400)),
        _document = initialDocument != null
            ? _deepCopyMap(initialDocument)
            : UserConfigDefaults.document();

  final SharedPreferences? _prefsOverride;

  /// When true, never touch the filesystem (tests / in-memory).
  final bool memoryOnly;

  /// Delay before coalesced disk/prefs write. Zero = flush on each mutation
  /// (default for [memoryOnly] so widget tests leave no pending [Timer]s).
  final Duration _persistDebounce;

  Map<String, dynamic> _document;
  String? _resolvedPath;
  String? _pathOverride;
  String? _defaultPath;
  bool _ready = false;
  bool _usesFilesystem = false;

  Timer? _persistDebounceTimer;
  bool _persistDirty = false;
  Future<void>? _inFlightPersist;

  /// How many debounced flush operations ran ([UserConfigStore] tests).
  @visibleForTesting
  int persistOperationCount = 0;

  bool get isReady => _ready;

  /// Whether a disk write is scheduled or in progress.
  bool get hasPendingPersist =>
      _persistDirty || _persistDebounceTimer != null || _inFlightPersist != null;

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

    var shouldPersist = false;
    if (loaded == null || loaded.isEmpty) {
      _document = <String, dynamic>{};
    } else {
      _document = loaded;
      if (_document[UserConfigKeys.version] is! int) {
        _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
        shouldPersist = true;
      }
    }

    // Absorb any leftover legacy keys once, then drop them — before
    // defaults so migrated slices are not treated as "already present".
    final migrated = await _migrateLegacy(prefs);
    if (migrated) {
      shouldPersist = true;
      await _clearLegacy(prefs);
    }

    if (UserConfigDefaults.mergeInto(_document)) {
      shouldPersist = true;
    }
    if (UserConfigDefaults.sanitizeInto(_document)) {
      shouldPersist = true;
    }

    if (shouldPersist) {
      await _persistWithoutDebounce();
    }

    _ready = true;
    notifyListeners();
  }

  /// Replace one top-level slice and schedule a debounced persist.
  ///
  /// Completes after the in-memory update (does not wait for disk). Call
  /// [flushPersist] when durability is required before continuing.
  Future<void> setSlice(String key, Object? value) async {
    if (value == null) {
      _document.remove(key);
    } else {
      _document[key] = value is Map
          ? _deepCopyMap(Map<String, dynamic>.from(value))
          : value;
    }
    notifyListeners();
    _scheduleDebouncedPersist();
  }

  /// Mutate the document in place, then schedule a debounced persist.
  ///
  /// Completes after the in-memory update (does not wait for disk).
  Future<void> update(void Function(Map<String, dynamic> doc) mutate) async {
    mutate(_document);
    notifyListeners();
    _scheduleDebouncedPersist();
  }

  /// Writes the in-memory document to durable storage now.
  ///
  /// Call after Import or before Export when disk must match memory, and on
  /// app pause/background.
  Future<void> flushPersist() => _flushPersistNow();

  /// Replace the whole document from Import (JSON text).
  Future<void> importJson(String raw) async {
    final parsed = _tryParseDocument(raw);
    if (parsed == null) {
      throw const FormatException('Invalid Omniscope config JSON.');
    }
    _abortPendingPersist();
    _document = parsed;
    if (_document[UserConfigKeys.version] is! int) {
      _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
    }
    UserConfigDefaults.mergeInto(_document);
    UserConfigDefaults.sanitizeInto(_document);
    await _persistWithoutDebounce();
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
    await _persistWithoutDebounce();
    notifyListeners();
  }

  void _abortPendingPersist() {
    _cancelDebouncedPersist();
    _persistDirty = false;
  }

  Future<void> _persistWithoutDebounce() async {
    _abortPendingPersist();
    await _persistImmediate();
  }

  void _cancelDebouncedPersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;
  }

  void _scheduleDebouncedPersist() {
    _persistDirty = true;
    if (_persistDebounce <= Duration.zero) {
      unawaited(_flushPersistNow());
      return;
    }
    _cancelDebouncedPersist();
    _persistDebounceTimer = Timer(_persistDebounce, () {
      unawaited(_flushPersistNow());
    });
  }

  Future<void> _flushPersistNow() async {
    _cancelDebouncedPersist();
    if (_inFlightPersist != null) {
      await _inFlightPersist;
    }
    if (!_persistDirty) return;
    _persistDirty = false;
    final run = _persistImmediate();
    _inFlightPersist = run;
    try {
      await run;
    } finally {
      if (identical(_inFlightPersist, run)) {
        _inFlightPersist = null;
      }
    }
    if (_persistDirty) {
      _scheduleDebouncedPersist();
    }
  }

  Future<void> _persistImmediate() async {
    final existing = _document[UserConfigKeys.version];
    if (existing is! int ||
        existing >= UserConfigKeys.currentVersion) {
      _document[UserConfigKeys.version] = UserConfigKeys.currentVersion;
    }
    final encoded = jsonEncode(_document);

    persistOperationCount++;

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
