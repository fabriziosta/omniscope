import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

class LlmModelOption {
  const LlmModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.weight = ModelWeight.light,
  });

  final String id;
  final String label;
  final bool isDefault;
  final ModelWeight weight;

  factory LlmModelOption.fromJson(Map<String, dynamic> json) {
    return LlmModelOption(
      id: json['id'] as String,
      label: json['label'] as String? ?? json['id'] as String,
      isDefault: json['default'] as bool? ?? false,
      weight: ModelWeightX.parse(json['weight'] as String?),
    );
  }
}

/// Loads selectable LLM models from [assets/agents/llm_models.json].
///
/// Keep the JSON schema stable so a future remote refresh can feed the same
/// [modelsFor] / [defaultModelId] API without changing UI code.
class LlmModelCatalog {
  LlmModelCatalog._(this._byProvider);

  static const assetPath = 'assets/agents/llm_models.json';

  final Map<LlmProvider, List<LlmModelOption>> _byProvider;

  List<LlmModelOption> modelsFor(LlmProvider provider) {
    if (provider == LlmProvider.custom) return const [];
    return _byProvider[provider] ?? const [];
  }

  String? defaultModelId(LlmProvider provider) {
    final models = modelsFor(provider);
    if (models.isEmpty) return null;
    for (final m in models) {
      if (m.isDefault) return m.id;
    }
    return models.first.id;
  }

  /// Prefer the role's suggested model; otherwise first model matching [weight].
  String? suggestedModelId(
    LlmProvider provider, {
    String? preferredId,
    ModelWeight? preferredWeight,
  }) {
    final models = modelsFor(provider);
    if (models.isEmpty) return null;
    if (preferredId != null &&
        preferredId.isNotEmpty &&
        models.any((m) => m.id == preferredId)) {
      return preferredId;
    }
    if (preferredWeight != null) {
      for (final m in models) {
        if (m.weight == preferredWeight) return m.id;
      }
    }
    return defaultModelId(provider);
  }

  String? labelFor(LlmProvider provider, String modelId) {
    for (final m in modelsFor(provider)) {
      if (m.id == modelId) return m.label;
    }
    return null;
  }

  static Future<LlmModelCatalog> load({
    AssetBundle? bundle,
    String path = assetPath,
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(path);
    return LlmModelCatalog.parse(raw);
  }

  static LlmModelCatalog parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final providers = json['providers'] as Map<String, dynamic>? ?? const {};
    final byProvider = <LlmProvider, List<LlmModelOption>>{};

    for (final provider in LlmProvider.values) {
      if (provider == LlmProvider.custom) continue;
      final list = providers[provider.catalogKey] as List? ?? const [];
      byProvider[provider] = [
        for (final item in list)
          LlmModelOption.fromJson(item as Map<String, dynamic>),
      ];
    }

    return LlmModelCatalog._(byProvider);
  }
}
