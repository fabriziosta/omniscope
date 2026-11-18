import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/data/agents/llm_connection_health.dart';
import 'package:omniscope/data/agents/llm_connection_probe.dart';
import 'package:omniscope/data/agents/llm_model_router.dart';
import 'package:omniscope/data/agents/models.dart';

void main() {
  group('LlmConnectionHealth.classify', () {
    test('maps 401/403 to invalidKey', () {
      expect(
        LlmConnectionHealth.classify(statusCode: 401),
        LlmConnectionKind.invalidKey,
      );
      expect(
        LlmConnectionHealth.classify(statusCode: 403),
        LlmConnectionKind.invalidKey,
      );
    });

    test('maps 429 to rateLimited', () {
      expect(
        LlmConnectionHealth.classify(statusCode: 429),
        LlmConnectionKind.rateLimited,
      );
    });

    test('maps 5xx and network text to unreachable', () {
      expect(
        LlmConnectionHealth.classify(statusCode: 503),
        LlmConnectionKind.unreachable,
      );
      expect(
        LlmConnectionHealth.classify(
          message: 'ClientException: Failed host lookup',
        ),
        LlmConnectionKind.unreachable,
      );
    });

    test('detects auth wording without status', () {
      expect(
        LlmConnectionHealth.classify(
          message: 'OpenAI API error: Incorrect API key provided',
        ),
        LlmConnectionKind.invalidKey,
      );
    });
  });

  group('LlmConnectionProbe', () {
    LlmResolvedEndpoint endpoint(LlmProvider provider, {String? baseUrl}) {
      return LlmResolvedEndpoint(
        provider: provider,
        apiKey: 'test-key',
        modelId: 'model',
        weight: ModelWeight.light,
        baseUrl: baseUrl,
      );
    }

    test('returns ok on 200 for OpenAI models', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.host, 'api.openai.com');
        expect(request.url.path, '/v1/models');
        expect(request.headers['Authorization'], 'Bearer test-key');
        return http.Response('{"data":[]}', 200);
      });
      final probe = LlmConnectionProbe(httpClient: client);
      final result = await probe.probe(endpoint(LlmProvider.openAi));
      expect(result.kind, LlmConnectionKind.ok);
      expect(result.statusCode, 200);
    });

    test('returns invalidKey on 401', () async {
      final client = MockClient(
        (_) async => http.Response('unauthorized', 401),
      );
      final probe = LlmConnectionProbe(httpClient: client);
      final result = await probe.probe(endpoint(LlmProvider.gemini));
      expect(result.kind, LlmConnectionKind.invalidKey);
      expect(result.statusCode, 401);
    });

    test('returns unreachable on socket-style failure', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('Failed host lookup'),
      );
      final probe = LlmConnectionProbe(httpClient: client);
      final result = await probe.probe(endpoint(LlmProvider.anthropic));
      expect(result.kind, LlmConnectionKind.unreachable);
    });

    test('requires Custom base URL', () async {
      final probe = LlmConnectionProbe(
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      final result = await probe.probe(endpoint(LlmProvider.custom));
      expect(result.kind, LlmConnectionKind.unsupported);
    });

    test('joins Custom base URL with /models', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/v1/models');
        return http.Response('{}', 200);
      });
      final probe = LlmConnectionProbe(httpClient: client);
      final result = await probe.probe(
        endpoint(LlmProvider.custom, baseUrl: 'https://example.com/v1/'),
      );
      expect(result.kind, LlmConnectionKind.ok);
    });

    test('sends Anthropic auth headers', () async {
      final client = MockClient((request) async {
        expect(request.headers['x-api-key'], 'test-key');
        expect(request.headers['anthropic-version'], '2023-06-01');
        return http.Response('{}', 200);
      });
      final probe = LlmConnectionProbe(httpClient: client);
      final result = await probe.probe(endpoint(LlmProvider.anthropic));
      expect(result.isOk, isTrue);
    });
  });
}
