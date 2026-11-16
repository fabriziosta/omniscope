import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'llm_model_catalog.dart';
import 'models.dart';

/// Per-provider light/heavy model preferences (Settings → Connections).
class LlmProviderRuntimePrefs {
  const LlmProviderRuntimePrefs({
    required this.provider,
    this.lightModelId = '',
    this.heavyModelId = '',
    this.baseUrl,
    this.priority = 100,
    this.enabled = true,
  });

  final LlmProvider provider;
  final String lightModelId;
  final String heavyModelId;
  final String? baseUrl;
  final int priority;
  final bool enabled;

  String modelIdFor(ModelWeight weight) => switch (weight) {
        ModelWeight.light => lightModelId.trim(),
        ModelWeight.heavy => heavyModelId.trim(),
      };

  /// Prefer [weight]; fall back to the other weight if only one is set.
  String? resolvedModelId(ModelWeight weight) {
    final primary = modelIdFor(weight);
    if (primary.isNotEmpty) return primary;
    final other = modelIdFor(
      weight == ModelWeight.light ? ModelWeight.heavy : ModelWeight.light,
    );
    return other.isEmpty ? null : other;
  }

  LlmProviderRuntimePrefs copyWith({
    LlmProvider? provider,
    String? lightModelId,
    String? heavyModelId,
    String? baseUrl,
    bool clearBaseUrl = false,
    int? priority,
    bool? enabled,
  }) {
    return LlmProviderRuntimePrefs(
      provider: provider ?? this.provider,
      lightModelId: lightModelId ?? this.lightModelId,
      heavyModelId: heavyModelId ?? this.heavyModelId,
      baseUrl: clearBaseUrl ? null : (baseUrl ?? this.baseUrl),
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'lightModelId': lightModelId,
        'heavyModelId': heavyModelId,
        if (baseUrl != null && baseUrl!.trim().isNotEmpty) 'baseUrl': baseUrl,
        'priority': priority,
        'enabled': enabled,
      };

  factory LlmProviderRuntimePrefs.fromJson(Map<String, dynamic> json) {
    final raw = json['provider'] as String? ?? 'gemini';
    final provider = LlmProvider.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => LlmProvider.gemini,
    );
    return LlmProviderRuntimePrefs(
      provider: provider,
      lightModelId: json['lightModelId'] as String? ?? '',
      heavyModelId: json['heavyModelId'] as String? ?? '',
      baseUrl: json['baseUrl'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// Defaults from [catalog] when models are blank.
  factory LlmProviderRuntimePrefs.withCatalogDefaults({
    required LlmProvider provider,
    required LlmModelCatalog catalog,
    String? lightModelId,
    String? heavyModelId,
    String? baseUrl,
    int priority = 100,
    bool enabled = true,
  }) {
    return LlmProviderRuntimePrefs(
      provider: provider,
      lightModelId: lightModelId?.trim().isNotEmpty == true
          ? lightModelId!.trim()
          : (catalog.suggestedModelId(
                provider,
                preferredWeight: ModelWeight.light,
              ) ??
              ''),
      heavyModelId: heavyModelId?.trim().isNotEmpty == true
          ? heavyModelId!.trim()
          : (catalog.suggestedModelId(
                provider,
                preferredWeight: ModelWeight.heavy,
              ) ??
              ''),
      baseUrl: baseUrl,
      priority: priority,
      enabled: enabled,
    );
  }
}

/// Persisted multi-provider LLM runtime preferences.
class LlmRuntimeSettings extends ChangeNotifier {
  LlmRuntimeSettings({this.store});

  UserConfigStore? store;
  final Map<LlmProvider, LlmProviderRuntimePrefs> _byProvider = {};
  bool _ready = false;

  bool get isReady => _ready;

  List<LlmProviderRuntimePrefs> get providers {
    final list = _byProvider.values.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  LlmProviderRuntimePrefs? prefsFor(LlmProvider provider) =>
      _byProvider[provider];

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _byProvider.clear();
    final slice = this.store?.getSlice(UserConfigKeys.llmRuntime);
    if (slice is Map) {
      try {
        final raw = slice['providers'] as List? ?? const [];
        for (final item in raw) {
          if (item is! Map) continue;
          final prefs = LlmProviderRuntimePrefs.fromJson(
            Map<String, dynamic>.from(item),
          );
          _byProvider[prefs.provider] = prefs;
        }
      } catch (_) {
        _byProvider.clear();
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.llmRuntime, {
      'providers': [for (final p in providers) p.toJson()],
    });
  }

  Future<void> upsert(LlmProviderRuntimePrefs prefs) async {
    _byProvider[prefs.provider] = prefs;
    await _persist();
    notifyListeners();
  }

  Future<void> clearProvider(LlmProvider provider) async {
    _byProvider.remove(provider);
    await _persist();
    notifyListeners();
  }

  /// Remove all provider light/heavy prefs.
  Future<void> clearAll() async {
    _byProvider.clear();
    await _persist();
    notifyListeners();
  }

  /// Ensure prefs exist for [provider] using catalog defaults when missing.
  Future<LlmProviderRuntimePrefs> ensurePrefs({
    required LlmProvider provider,
    required LlmModelCatalog catalog,
    String? baseUrl,
  }) async {
    final existing = _byProvider[provider];
    if (existing != null) {
      if (baseUrl != null &&
          baseUrl.trim().isNotEmpty &&
          (existing.baseUrl == null || existing.baseUrl!.trim().isEmpty)) {
        final next = existing.copyWith(baseUrl: baseUrl.trim());
        await upsert(next);
        return next;
      }
      return existing;
    }
    final created = LlmProviderRuntimePrefs.withCatalogDefaults(
      provider: provider,
      catalog: catalog,
      baseUrl: baseUrl,
    );
    await upsert(created);
    return created;
  }

  /// Promote legacy per-role [AgentConnection] model picks into runtime prefs.
  Future<void> migrateFromConnections({
    required Iterable<AgentConnection> connections,
    required LlmModelCatalog catalog,
  }) async {
    var changed = false;
    for (final c in connections) {
      if (!c.connected || !c.isConfigured) continue;
      final existing = _byProvider[c.llmProvider];
      final weight = switch (c.roleId) {
        'intradayTrading' => ModelWeight.heavy,
        _ => ModelWeight.light,
      };
      if (existing == null) {
        final light = weight == ModelWeight.light
            ? c.modelId
            : (catalog.suggestedModelId(
                  c.llmProvider,
                  preferredWeight: ModelWeight.light,
                ) ??
                c.modelId);
        final heavy = weight == ModelWeight.heavy
            ? c.modelId
            : (catalog.suggestedModelId(
                  c.llmProvider,
                  preferredWeight: ModelWeight.heavy,
                ) ??
                c.modelId);
        _byProvider[c.llmProvider] = LlmProviderRuntimePrefs(
          provider: c.llmProvider,
          lightModelId: light,
          heavyModelId: heavy,
          baseUrl: c.baseUrl,
          priority: _byProvider.length * 10,
        );
        changed = true;
      } else {
        final model = c.modelId.trim();
        if (model.isEmpty) continue;
        if (weight == ModelWeight.light &&
            existing.lightModelId.trim().isEmpty) {
          _byProvider[c.llmProvider] =
              existing.copyWith(lightModelId: model);
          changed = true;
        } else if (weight == ModelWeight.heavy &&
            existing.heavyModelId.trim().isEmpty) {
          _byProvider[c.llmProvider] =
              existing.copyWith(heavyModelId: model);
          changed = true;
        }
      }
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }
}
