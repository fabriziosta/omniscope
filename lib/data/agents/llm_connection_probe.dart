import 'package:http/http.dart' as http;

import 'llm_connection_health.dart';
import 'llm_model_router.dart';
import 'models.dart';

/// Cheap authenticated reachability check via provider list-models endpoints.
///
/// Does **not** call generate / spend completion tokens.
class LlmConnectionProbe {
  LlmConnectionProbe({http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final http.Client _http;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _http.close();
  }

  /// Probe [endpoint]'s provider with its API key (and Custom base URL).
  Future<LlmConnectionResult> probe(LlmResolvedEndpoint endpoint) async {
    final key = endpoint.apiKey.trim();
    if (key.isEmpty) {
      return const LlmConnectionResult(
        kind: LlmConnectionKind.unsupported,
        message: 'Enter an API key first.',
      );
    }
    if (endpoint.provider == LlmProvider.custom) {
      final base = endpoint.baseUrl?.trim() ?? '';
      if (base.isEmpty) {
        return const LlmConnectionResult(
          kind: LlmConnectionKind.unsupported,
          message: 'Base URL is required for Custom.',
        );
      }
    }

    try {
      final request = _buildRequest(endpoint, key);
      final response = await _http
          .send(request)
          .timeout(const Duration(seconds: 20));
      final status = response.statusCode;
      // Drain body so the connection can be reused; ignore content.
      await response.stream.drain<void>();
      if (status >= 200 && status < 300) {
        return LlmConnectionHealth.ok(statusCode: status);
      }
      return LlmConnectionHealth.fromHttpStatus(status);
    } catch (e) {
      return LlmConnectionHealth.fromError(e);
    }
  }

  http.BaseRequest _buildRequest(LlmResolvedEndpoint endpoint, String key) {
    return switch (endpoint.provider) {
      LlmProvider.gemini => http.Request(
          'GET',
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models'
            '?pageSize=1&key=${Uri.encodeQueryComponent(key)}',
          ),
        ),
      LlmProvider.openAi => _bearerGet(
          'https://api.openai.com/v1/models',
          key,
        ),
      LlmProvider.deepSeek => _bearerGet(
          'https://api.deepseek.com/models',
          key,
        ),
      LlmProvider.grok => _bearerGet(
          'https://api.x.ai/v1/models',
          key,
        ),
      LlmProvider.anthropic => () {
          final req = http.Request(
            'GET',
            Uri.parse('https://api.anthropic.com/v1/models'),
          );
          req.headers['x-api-key'] = key;
          req.headers['anthropic-version'] = '2023-06-01';
          return req;
        }(),
      LlmProvider.custom => _bearerGet(
          _joinModelsUrl(endpoint.baseUrl!.trim()),
          key,
        ),
    };
  }

  static http.Request _bearerGet(String url, String key) {
    final req = http.Request('GET', Uri.parse(url));
    req.headers['Authorization'] = 'Bearer $key';
    return req;
  }

  /// Append `/models` to a Custom OpenAI-compatible base URL.
  static String _joinModelsUrl(String rawBase) {
    final base = rawBase.replaceAll(RegExp(r'/+$'), '');
    if (base.toLowerCase().endsWith('/models')) return base;
    return '$base/models';
  }
}
