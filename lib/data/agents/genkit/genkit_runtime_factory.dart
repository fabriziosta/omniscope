import 'package:genkit/genkit.dart';
import 'package:genkit_anthropic/genkit_anthropic.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Builds a per-turn [Genkit] instance + [ModelRef] from the user's Connect
/// settings (bring-your-own-key).
class GenkitRuntimeFactory {
  GenkitRuntimeFactory({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  /// Plugin + model wired for [connection]. Throws [GenkitAgentException] if
  /// the connection is incomplete.
  ({Genkit ai, ModelRef model}) create(AgentConnection connection) {
    if (!connection.connected || !connection.isConfigured) {
      throw GenkitAgentException('Connect this agent before chatting.');
    }

    final key = connection.apiKey.trim();
    final modelId = connection.modelId.trim();
    if (key.isEmpty || modelId.isEmpty) {
      throw GenkitAgentException('Connect this agent before chatting.');
    }

    return switch (connection.llmProvider) {
      LlmProvider.gemini => (
          ai: Genkit(
            plugins: [googleAI(apiKey: key)],
            model: googleAI.gemini(modelId),
          ),
          model: googleAI.gemini(modelId),
        ),
      LlmProvider.openAi => (
          ai: Genkit(
            plugins: [openAI(apiKey: key, httpClient: _http)],
            model: openAI.model(modelId),
          ),
          model: openAI.model(modelId),
        ),
      LlmProvider.deepSeek => (
          ai: Genkit(
            plugins: [deepSeek(apiKey: key, httpClient: _http)],
            model: deepSeek.model(modelId),
          ),
          model: deepSeek.model(modelId),
        ),
      LlmProvider.grok => (
          ai: Genkit(
            plugins: [xAI(apiKey: key, httpClient: _http)],
            model: xAI.model(modelId),
          ),
          model: xAI.model(modelId),
        ),
      LlmProvider.anthropic => (
          ai: Genkit(
            plugins: [anthropic(apiKey: key, httpClient: _http)],
            model: anthropic.model(modelId),
          ),
          model: anthropic.model(modelId),
        ),
      LlmProvider.custom => () {
          final raw = connection.baseUrl?.trim() ?? '';
          if (raw.isEmpty) {
            throw GenkitAgentException('Base URL is required for Custom.');
          }
          final base = raw.replaceAll(RegExp(r'/+$'), '');
          return (
            ai: Genkit(
              plugins: [
                openAI(
                  apiKey: key,
                  baseUrl: base,
                  httpClient: _http,
                  name: 'custom',
                ),
              ],
              model: openAI.model(modelId, namespace: 'custom'),
            ),
            model: openAI.model(modelId, namespace: 'custom'),
          );
        }(),
    };
  }
}

/// Thrown when Genkit agent setup or a turn fails in a user-visible way.
class GenkitAgentException implements Exception {
  GenkitAgentException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'GenkitAgentException($statusCode): $message';
}
