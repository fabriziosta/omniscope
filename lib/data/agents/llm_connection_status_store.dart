import 'package:flutter/foundation.dart';

import 'llm_connection_health.dart';
import 'llm_connection_probe.dart';
import 'llm_model_router.dart';
import 'llm_runtime_settings.dart';
import 'models.dart';

/// Session-only last probe results per [LlmProvider] (not persisted).
class LlmConnectionStatusStore extends ChangeNotifier {
  LlmConnectionStatusStore({LlmConnectionProbe? probe})
      : _probe = probe ?? LlmConnectionProbe();

  final LlmConnectionProbe _probe;
  final Map<LlmProvider, LlmConnectionResult> _results = {};
  final Set<LlmProvider> _probing = {};

  LlmConnectionResult? resultFor(LlmProvider provider) => _results[provider];

  bool isProbing(LlmProvider provider) => _probing.contains(provider);

  void clear(LlmProvider provider) {
    _results.remove(provider);
    _probing.remove(provider);
    notifyListeners();
  }

  void clearAll() {
    _results.clear();
    _probing.clear();
    notifyListeners();
  }

  /// Build an endpoint for [provider] from saved key + prefs, then probe.
  Future<LlmConnectionResult> probeProvider({
    required LlmProvider provider,
    required String apiKey,
    required LlmProviderRuntimePrefs? prefs,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      final result = const LlmConnectionResult(
        kind: LlmConnectionKind.unsupported,
        message: 'Enter an API key first.',
      );
      _results[provider] = result;
      notifyListeners();
      return result;
    }

    final light = prefs?.lightModelId.trim() ?? '';
    final heavy = prefs?.heavyModelId.trim() ?? '';
    final modelId = light.isNotEmpty ? light : heavy;
    if (modelId.isEmpty) {
      final result = const LlmConnectionResult(
        kind: LlmConnectionKind.unsupported,
        message: 'Pick at least one light or heavy model.',
      );
      _results[provider] = result;
      notifyListeners();
      return result;
    }

    if (provider == LlmProvider.custom) {
      final base = prefs?.baseUrl?.trim() ?? '';
      if (base.isEmpty) {
        final result = const LlmConnectionResult(
          kind: LlmConnectionKind.unsupported,
          message: 'Base URL is required for Custom.',
        );
        _results[provider] = result;
        notifyListeners();
        return result;
      }
    }

    final endpoint = LlmResolvedEndpoint(
      provider: provider,
      apiKey: key,
      modelId: modelId,
      weight: light.isNotEmpty ? ModelWeight.light : ModelWeight.heavy,
      baseUrl: prefs?.baseUrl,
    );

    return probeEndpoint(endpoint);
  }

  Future<LlmConnectionResult> probeEndpoint(LlmResolvedEndpoint endpoint) async {
    final provider = endpoint.provider;
    _probing.add(provider);
    notifyListeners();
    try {
      final result = await _probe.probe(endpoint);
      _results[provider] = result;
      return result;
    } finally {
      _probing.remove(provider);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _probe.close();
    super.dispose();
  }
}
