import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/llm_model_router.dart';
import 'package:omniscope/data/agents/market_context_builder.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/market/models.dart';

import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

FakeMarketDataClient _agentMarketData() => FakeMarketDataClient(
      basePrice: 190,
      fixedName: 'Apple',
      changePercent: 0.012,
      previousClose: 188,
      dataSource: 'Yahoo Finance',
      history: [
        Candle(
          time: DateTime.utc(2026, 1, 1),
          close: 180,
          high: 182,
          low: 178,
        ),
        Candle(
          time: DateTime.utc(2026, 1, 30),
          close: 190,
          high: 192,
          low: 185,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentChatRepository', () {
    test('persists chatId threads and trims overflow', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      final created = await repo.createChat(title: 'Research');
      expect(repo.threadFor(created.chatId).isEmpty, isTrue);

      await repo.append(
        chatId: created.chatId,
        message: AgentChatMessage(
          id: 'u1',
          role: AgentChatRole.user,
          content: 'Investigate AAPL',
          createdAt: DateTime.utc(2026, 1, 1),
          kind: AgentChatMessageKind.run,
        ),
      );
      await repo.append(
        chatId: created.chatId,
        message: AgentChatMessage(
          id: 'a1',
          role: AgentChatRole.assistant,
          content: 'Brief…',
          createdAt: DateTime.utc(2026, 1, 1, 0, 1),
        ),
      );

      final reloaded = AgentChatRepository(store: store);
      await reloaded.load();
      final thread = reloaded.threadFor(created.chatId);
      expect(thread.messages, hasLength(2));
      expect(thread.messages.first.content, 'Investigate AAPL');
      expect(thread.messages.last.role, AgentChatRole.assistant);

      for (var i = 0; i < AgentChatRepository.maxMessagesPerThread + 5; i++) {
        await repo.append(
          chatId: created.chatId,
          message: AgentChatMessage(
            id: 'x$i',
            role: AgentChatRole.user,
            content: 'm$i',
            createdAt: DateTime.utc(2026, 1, 2).add(Duration(seconds: i)),
          ),
        );
      }
      expect(
        repo.threadFor(created.chatId).messages,
        hasLength(AgentChatRepository.maxMessagesPerThread),
      );

      await repo.clearThread(created.chatId);
      expect(repo.threadFor(created.chatId).isEmpty, isTrue);
    });

    test('renameChat updates title and persists', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      final created = await repo.createChat(title: 'Draft');
      await repo.renameChat(created.chatId, '  Renamed research  ');
      expect(repo.threadFor(created.chatId).title, 'Renamed research');

      final reloaded = AgentChatRepository(store: store);
      await reloaded.load();
      expect(reloaded.threadFor(created.chatId).title, 'Renamed research');

      await repo.renameChat(created.chatId, '   ');
      expect(repo.threadFor(created.chatId).title, 'Renamed research');
    });

    test('pinned chats stay on top and persist; append keeps pin', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      final older = await repo.createChat(title: 'Older');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final newer = await repo.createChat(title: 'Newer');
      expect(repo.threads.map((t) => t.chatId).toList(), [
        newer.chatId,
        older.chatId,
      ]);

      await repo.setPinned(older.chatId, pinned: true);
      expect(repo.threads.map((t) => t.chatId).toList(), [
        older.chatId,
        newer.chatId,
      ]);
      expect(repo.threadFor(older.chatId).pinned, isTrue);

      await repo.append(
        chatId: older.chatId,
        message: AgentChatMessage(
          id: 'u1',
          role: AgentChatRole.user,
          content: 'Still pinned',
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );
      expect(repo.threadFor(older.chatId).pinned, isTrue);

      final reloaded = AgentChatRepository(store: store);
      await reloaded.load();
      expect(reloaded.threads.first.chatId, older.chatId);
      expect(reloaded.threadFor(older.chatId).pinned, isTrue);

      await repo.togglePinned(older.chatId);
      expect(repo.threadFor(older.chatId).pinned, isFalse);
      // Append bumped older.updatedAt, so it still leads among unpinned.
      expect(repo.threads.map((t) => t.chatId).toList(), [
        older.chatId,
        newer.chatId,
      ]);

      await repo.setPinned(newer.chatId, pinned: true);
      expect(repo.threads.map((t) => t.chatId).toList(), [
        newer.chatId,
        older.chatId,
      ]);
    });

    test('findThread resolves by chatId or sourceMessageId', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      final created = await repo.createChat(title: 'Ops');
      await repo.append(
        chatId: created.chatId,
        message: AgentChatMessage(
          id: 'msg_assist',
          role: AgentChatRole.assistant,
          content: 'Proposal ready',
          createdAt: DateTime.utc(2026, 1, 1),
          proposalId: 'tp_1',
        ),
      );

      expect(
        repo.findThread(chatId: created.chatId)?.chatId,
        created.chatId,
      );
      expect(
        repo.findThread(sourceMessageId: 'msg_assist')?.chatId,
        created.chatId,
      );
      expect(repo.findThread(chatId: 'missing'), isNull);
      expect(repo.findThread(sourceMessageId: 'missing'), isNull);
      expect(
        repo.threadHasPendingProposal(
          created.chatId,
          isPending: (id) => id == 'tp_1',
        ),
        isTrue,
      );
      expect(
        repo.threadHasPendingProposal(
          created.chatId,
          isPending: (_) => false,
        ),
        isFalse,
      );
    });

    test('clearAllThreads wipes every chat', () async {
      final store = await memoryConfig();
      final repo = AgentChatRepository(store: store);
      await repo.load();

      final a = await repo.createChat(title: 'A');
      final b = await repo.createChat(title: 'B');
      await repo.append(
        chatId: a.chatId,
        message: AgentChatMessage(
          id: 'u1',
          role: AgentChatRole.user,
          content: 'Hello',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.append(
        chatId: b.chatId,
        message: AgentChatMessage(
          id: 'u2',
          role: AgentChatRole.user,
          content: 'Hi',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(repo.threadFor(a.chatId).isEmpty, isFalse);
      expect(repo.threadFor(b.chatId).isEmpty, isFalse);

      await repo.clearAllThreads();
      expect(repo.threads, isEmpty);

      final again = AgentChatRepository(store: store);
      await again.load();
      expect(again.threads, isEmpty);
    });
  });

  group('AgentChatThread.plainTextExchange', () {
    test('formats user and assistant turns for clipboard', () {
      final thread = AgentChatThread(
        chatId: 'c1',
        title: 'AAPL',
        updatedAt: DateTime.utc(2026, 1, 1),
        messages: [
          AgentChatMessage(
            id: 'u1',
            role: AgentChatRole.user,
            content: '  Investigate AAPL  ',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
          AgentChatMessage(
            id: 's1',
            role: AgentChatRole.system,
            content: 'hidden',
            createdAt: DateTime.utc(2026, 1, 1, 0, 1),
          ),
          AgentChatMessage(
            id: 'a1',
            role: AgentChatRole.assistant,
            content: 'Brief on AAPL',
            createdAt: DateTime.utc(2026, 1, 1, 0, 2),
          ),
        ],
      );

      expect(
        thread.plainTextExchange,
        'You [2026-01-01T00:00:00.000Z]:\nInvestigate AAPL\n\n'
        'Agent [2026-01-01T00:02:00.000Z]:\nBrief on AAPL',
      );
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
          roleId: 'liveBalanceExplainer',
          symbol: '',
        ),
        allOf(
          contains('live exchange balances'),
          contains('Do not emit trade JSON'),
        ),
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'liveBalanceExplainer',
          symbol: 'BTC',
        ),
        contains('BTC'),
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'portfolioGuide',
          symbol: '',
        ),
        contains('allocation'),
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'paperPortfolioCoach',
          symbol: 'AAPL',
          side: 'buy',
          quantity: 2,
        ),
        allOf(contains('AAPL'), contains('buy'), contains('2')),
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
      expect(
        AgentRolePrompts.runChipLabel('liveBalanceExplainer'),
        'Explain balances',
      );
      expect(
        AgentRolePrompts.runChipLabel('portfolioGuide'),
        'Review allocation',
      );
      expect(
        AgentRolePrompts.runChipLabel('paperPortfolioCoach'),
        'Coach practice',
      );
      expect(AgentRolePrompts.supportsTradeProposals('liveBalanceExplainer'), isFalse);
      expect(AgentRolePrompts.usesLiveBalanceContext('liveBalanceExplainer'), isTrue);
      expect(AgentRolePrompts.usesLiveBalanceContext('portfolioGuide'), isTrue);
      expect(AgentRolePrompts.usesPracticePortfolioContext('portfolioGuide'), isTrue);
      expect(
        AgentRolePrompts.usesPracticePortfolioContext('paperPortfolioCoach'),
        isTrue,
      );
      expect(AgentRolePrompts.allowsRunWithoutSymbol('liveBalanceExplainer'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('portfolioGuide'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('paperPortfolioCoach'), isTrue);
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
      final builder = MarketContextBuilder(_agentMarketData());
      final snap = await builder.buildForSymbol('AAPL');
      expect(snap, isNotNull);
      expect(snap!, contains('AAPL'));
      expect(snap, contains('190'));
    });
  });

  group('GenkitAgentRunner', () {
    test('turn override returns canned assistant text', () async {
      final client = fakeGenkitAgentRunner(reply: 'Hello research');

      final turn = await client.complete(
        endpoint: const LlmResolvedEndpoint(
          provider: LlmProvider.openAi,
          apiKey: 'sk-test',
          modelId: 'gpt-6-luna',
          weight: ModelWeight.light,
        ),
        messages: [
          AgentChatMessage(
            id: '1',
            role: AgentChatRole.user,
            content: 'Investigate AAPL',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(turn.reply, 'Hello research');
      expect(turn.delegatedTradeJson, isNull);
    });
  });

  group('AgentChatMessage generation meta', () {
    test('formats duration and joins model · time', () {
      expect(AgentChatMessage.formatGenerationDuration(842), '842ms');
      expect(AgentChatMessage.formatGenerationDuration(1200), '1.2s');
      expect(AgentChatMessage.formatGenerationDuration(10500), '11s');
      expect(AgentChatMessage.formatGenerationDuration(65000), '1m 5s');

      final labeled = AgentChatMessage(
        id: 'a1',
        role: AgentChatRole.assistant,
        content: 'Hello',
        createdAt: DateTime.utc(2026, 1, 1),
        modelId: 'gemini-2.0-flash',
        generationMs: 1200,
      );
      expect(labeled.generationMetaLabel, 'gemini-2.0-flash · 1.2s');
      expect(
        AgentChatMessage(
          id: 'a2',
          role: AgentChatRole.assistant,
          content: 'Hi',
          createdAt: DateTime.utc(2026, 1, 1),
        ).generationMetaLabel,
        isNull,
      );
    });
  });
}
