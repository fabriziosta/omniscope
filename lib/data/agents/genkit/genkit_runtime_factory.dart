import 'package:genkit/genkit.dart';
import 'package:genkit_anthropic/genkit_anthropic.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_middleware/agents.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:http/http.dart' as http;

import '../llm_connection_health.dart';
import '../llm_model_router.dart';
import '../models.dart';

/// Builds a per-turn [Genkit] instance + [ModelRef] from a resolved endpoint.
class GenkitRuntimeFactory {
  GenkitRuntimeFactory({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  /// Plugin + model for [endpoint]. Always includes [AgentsPlugin].
  ({Genkit ai, ModelRef model}) create(LlmResolvedEndpoint endpoint) {
    if (!endpoint.isConfigured) {
      throw GenkitAgentException(
        'Add an LLM API key under Settings → Connections before chatting.',
      );
    }

    final model = modelRefFor(
      provider: endpoint.provider,
      modelId: endpoint.modelId,
    );
    final plugins = [
      ..._llmPlugins(endpoint),
      AgentsPlugin(),
    ];
    return (
      ai: Genkit(plugins: plugins, model: model),
      model: model,
    );
  }

  ModelRef modelRefFor({
    required LlmProvider provider,
    required String modelId,
  }) {
    final id = modelId.trim();
    return switch (provider) {
      LlmProvider.gemini => googleAI.gemini(id),
      LlmProvider.openAi => openAI.model(id),
      LlmProvider.deepSeek => deepSeek.model(id),
      LlmProvider.grok => xAI.model(id),
      LlmProvider.anthropic => anthropic.model(id),
      LlmProvider.custom => openAI.model(id, namespace: 'custom'),
    };
  }

  /// Same-provider specialty model override; else [primaryModel].
  ModelRef specialtyModel({
    required LlmResolvedEndpoint primary,
    required ModelRef primaryModel,
    required String? specialtyModelId,
  }) {
    final id = specialtyModelId?.trim() ?? '';
    if (id.isEmpty || id == primary.modelId.trim()) return primaryModel;
    return modelRefFor(provider: primary.provider, modelId: id);
  }

  List<GenkitPlugin> _llmPlugins(LlmResolvedEndpoint endpoint) {
    final key = endpoint.apiKey.trim();
    return switch (endpoint.provider) {
      LlmProvider.gemini => [googleAI(apiKey: key)],
      LlmProvider.openAi => [openAI(apiKey: key, httpClient: _http)],
      LlmProvider.deepSeek => [deepSeek(apiKey: key, httpClient: _http)],
      LlmProvider.grok => [xAI(apiKey: key, httpClient: _http)],
      LlmProvider.anthropic => [anthropic(apiKey: key)],
      LlmProvider.custom => () {
          final raw = endpoint.baseUrl?.trim() ?? '';
          if (raw.isEmpty) {
            throw GenkitAgentException('Base URL is required for Custom.');
          }
          final base = raw.replaceAll(RegExp(r'/+$'), '');
          return [
            openAI(
              apiKey: key,
              baseUrl: base,
              httpClient: _http,
              name: 'custom',
            ),
          ];
        }(),
    };
  }
}

/// Thrown when Genkit agent setup or a turn fails in a user-visible way.
class GenkitAgentException implements Exception {
  GenkitAgentException(
    this.message, {
    this.statusCode,
    this.connectionKind,
  });

  /// Map a provider / Genkit failure to plain copy + [connectionKind].
  factory GenkitAgentException.fromProviderError(Object error) {
    final raw = error.toString();
    final statusCode = _statusCodeFromError(error);
    final classified = LlmConnectionHealth.fromError(
      error,
      statusCode: statusCode,
    );
    final kind = classified.kind;
    // Prefer curated copy for auth / network / rate-limit; keep truncated
    // provider text otherwise so unusual errors stay diagnosable.
    final message = switch (kind) {
      LlmConnectionKind.invalidKey ||
      LlmConnectionKind.unreachable ||
      LlmConnectionKind.rateLimited =>
        LlmConnectionHealth.userMessage(kind),
      _ => raw.length > 240 ? '${raw.substring(0, 237)}…' : raw,
    };
    return GenkitAgentException(
      message,
      statusCode: classified.statusCode ?? statusCode,
      connectionKind: kind,
    );
  }

  final String message;
  final int? statusCode;
  final LlmConnectionKind? connectionKind;

  @override
  String toString() => 'GenkitAgentException($statusCode): $message';
}

int? _statusCodeFromError(Object error) {
  if (error is GenkitException) {
    return error.status.httpStatus;
  }
  final match = RegExp(r'\b([45]\d{2})\b').firstMatch(error.toString());
  return match == null ? null : int.tryParse(match.group(1)!);
}
