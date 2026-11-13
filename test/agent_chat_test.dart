import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/llm_chat_client.dart';
import 'package:omniscope/data/agents/market_context_builder.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/features/agents/agents_screen.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentChatRepository', () {
    test('persists one thread per role and trims overflow', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      expect(repo.threadFor('marketResearch').isEmpty, isTrue);

      await repo.append(
        roleId: 'marketResearch',
        message: AgentChatMessage(
          id: 'u1',
          role: AgentChatRole.user,
          content: 'Investigate AAPL',
          createdAt: DateTime.utc(2026, 1, 1),
          kind: AgentChatMessageKind.run,
        ),
      );
      await repo.append(
        roleId: 'marketResearch',
        message: AgentChatMessage(
          id: 'a1',
          role: AgentChatRole.assistant,
          content: 'Brief…',
          createdAt: DateTime.utc(2026, 1, 1, 0, 1),
        ),
      );

      final reloaded = AgentChatRepository(store: store);
      await reloaded.load();
      final thread = reloaded.threadFor('marketResearch');
      expect(thread.messages, hasLength(2));
      expect(thread.messages.first.content, 'Investigate AAPL');
      expect(thread.messages.last.role, AgentChatRole.assistant);

      for (var i = 0; i < AgentChatRepository.maxMessagesPerThread + 5; i++) {
        await repo.append(
          roleId: 'marketResearch',
          message: AgentChatMessage(
            id: 'x$i',
            role: AgentChatRole.user,
            content: 'm$i',
            createdAt: DateTime.utc(2026, 1, 2).add(Duration(seconds: i)),
          ),
        );
      }
      expect(
        repo.threadFor('marketResearch').messages,
        hasLength(AgentChatRepository.maxMessagesPerThread),
      );

      await repo.clearThread('marketResearch');
      expect(repo.threadFor('marketResearch').isEmpty, isTrue);
    });

    test('clearAllThreads wipes every role thread', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      await repo.append(
        roleId: 'marketResearch',
        message: AgentChatMessage(
          id: 'u1',
          role: AgentChatRole.user,
          content: 'Hello',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.append(
        roleId: 'trading',
        message: AgentChatMessage(
          id: 'u2',
          role: AgentChatRole.user,
          content: 'Hi',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(repo.threadFor('marketResearch').isEmpty, isFalse);
      expect(repo.threadFor('trading').isEmpty, isFalse);

      await repo.clearAllThreads();
      expect(repo.threadFor('marketResearch').isEmpty, isTrue);
      expect(repo.threadFor('trading').isEmpty, isTrue);

      final again = AgentChatRepository(store: store);
      await again.load();
      expect(again.threadFor('marketResearch').isEmpty, isTrue);
      expect(again.threadFor('trading').isEmpty, isTrue);
    });
  });

  group('AgentRolePrompts', () {
    test('builds role-aware run prompts', () {
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'marketResearch',
          symbol: 'aapl',
        ),
        contains('AAPL'),
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'intradayTrading',
          symbol: 'MSFT',
          side: 'buy',
          quantity: 5,
        ),
        allOf(contains('MSFT'), contains('buy'), contains('5')),
      );
      expect(AgentRolePrompts.runChipLabel('hedgeFundDesk'), 'Run desk');
    });
  });

  group('MarketContextBuilder', () {
    test('extracts ticker-like tokens', () {
      expect(
        MarketContextBuilder.extractSymbolHint('Please investigate AAPL today'),
        'AAPL',
      );
      expect(MarketContextBuilder.extractSymbolHint('hello'), isNull);
    });

    test('formats quote snapshot', () async {
      final builder = MarketContextBuilder(_FakeMarketData());
      final snap = await builder.buildForSymbol('AAPL');
      expect(snap, isNotNull);
      expect(snap!, contains('AAPL'));
      expect(snap, contains('190'));
    });
  });

  group('LlmChatClient', () {
    test('parses OpenAI-compatible chat completions', () async {
      final client = LlmChatClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/chat/completions'));
          expect(request.headers['Authorization'], 'Bearer sk-test');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'gpt-6-luna');
          final messages = body['messages'] as List;
          expect(messages.first['role'], 'system');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Hello research'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final text = await client.complete(
        connection: const AgentConnection(
          roleId: 'marketResearch',
          llmProvider: LlmProvider.openAi,
          apiKey: 'sk-test',
          modelId: 'gpt-6-luna',
          connected: true,
        ),
        roleId: 'marketResearch',
        messages: [
          AgentChatMessage(
            id: '1',
            role: AgentChatRole.user,
            content: 'Investigate AAPL',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        marketContext: 'Market snapshot for AAPL',
      );
      expect(text, 'Hello research');
    });

    test('surfaces provider HTTP errors', () async {
      final client = LlmChatClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API key'},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        () => client.complete(
          connection: const AgentConnection(
            roleId: 'marketResearch',
            llmProvider: LlmProvider.openAi,
            apiKey: 'bad',
            modelId: 'gpt-6-luna',
            connected: true,
          ),
          roleId: 'marketResearch',
          messages: const [],
        ),
        throwsA(
          isA<LlmChatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid API key'),
          ),
        ),
      );
    });

    test('parses Anthropic messages response', () async {
      final client = LlmChatClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.anthropic.com');
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Claude reply'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final text = await client.complete(
        connection: const AgentConnection(
          roleId: 'marketResearch',
          llmProvider: LlmProvider.anthropic,
          apiKey: 'sk-ant',
          modelId: 'claude-haiku-5-5',
          connected: true,
        ),
        roleId: 'marketResearch',
        messages: [
          AgentChatMessage(
            id: '1',
            role: AgentChatRole.user,
            content: 'Hi',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(text, 'Claude reply');
    });

    test('parses Gemini generateContent response', () async {
      final client = LlmChatClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'generativelanguage.googleapis.com');
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Gemini reply'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final text = await client.complete(
        connection: const AgentConnection(
          roleId: 'marketResearch',
          llmProvider: LlmProvider.gemini,
          apiKey: 'gem-key',
          modelId: 'gemini-3.5-flash-lite',
          connected: true,
        ),
        roleId: 'marketResearch',
        messages: [
          AgentChatMessage(
            id: '1',
            role: AgentChatRole.user,
            content: 'Hi',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(text, 'Gemini reply');
    });
  });

  testWidgets('connected agent card opens chat screen', (tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    await agents.connect(
      roleId: 'marketResearch',
      llmProvider: LlmProvider.openAi,
      apiKey: 'sk-test',
      modelId: 'gpt-6-luna',
    );
    final agentChats = AgentChatRepository(store: store);
    await agentChats.load();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(value: _FakeMarketData()),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          Provider<LlmChatClient>.value(
            value: LlmChatClient(
              httpClient: MockClient(
                (_) async => http.Response('{}', 400),
              ),
            ),
          ),
          ChangeNotifierProvider<EnvSecretsRepository>.value(
            value: EnvSecretsRepository(store: store, syncEnvFile: false),
          ),
        ],
        child: ShadApp(
          home: const AgentsScreen(),
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: BrandColors.lightScheme(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open chat'), findsOneWidget);
    await tester.tap(find.text('Open chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Run research'), findsOneWidget);
    expect(find.textContaining('Messages stay on this device'), findsOneWidget);
  });
}

class _FakeMarketData implements MarketDataClient {
  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    return [
      for (final s in symbols)
        Quote(
          symbol: s,
          price: 190,
          name: 'Apple',
          changePercent: 0.012,
          previousClose: 188,
          dataSource: 'Yahoo Finance',
        ),
    ];
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    return [
      Candle(time: DateTime.utc(2026, 1, 1), close: 180, high: 182, low: 178),
      Candle(time: DateTime.utc(2026, 1, 30), close: 190, high: 192, low: 185),
    ];
  }
}
