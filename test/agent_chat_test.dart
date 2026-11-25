import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/formatting.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/llm_model_router.dart';
import 'package:omniscope/data/agents/market_context_builder.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_controller.dart';

import 'support/agent_test_harness.dart';
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
    test('builds short role-aware run prompts', () {
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'marketResearch',
          symbol: 'aapl',
        ),
        'Investigate AAPL.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'liveBalanceExplainer',
          symbol: '',
        ),
        'Explain my live balances.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'liveBalanceExplainer',
          symbol: 'BTC',
        ),
        'Explain my live balances. Focus on BTC.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'portfolioGuide',
          symbol: '',
        ),
        'Review my portfolio.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'portfolioGuide',
          symbol: 'AAPL',
          side: 'buy',
          quantity: 2,
        ),
        'Review my portfolio. Focus on AAPL. Side: buy. Quantity: 2.0.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'intradayTrading',
          symbol: 'MSFT',
          side: 'buy',
          quantity: 5,
        ),
        'Trade check for MSFT. Chart it vs Invest interest / Mandate; '
        'ask Market Research to evaluate before any buy/sell. '
        'Side: buy. Quantity: 5.0.',
      );
      expect(
        AgentRolePrompts.runUserPrompt(
          roleId: 'intradayTrading',
          symbol: '',
        ),
        allOf(
          contains('Invest interest charts'),
          contains('Market Research'),
          isNot(contains(AgentRolePrompts.draftSymbolPlaceholder)),
        ),
      );
      expect(
        AgentRolePrompts.runChipLabel('liveBalanceExplainer'),
        'Explain balances',
      );
      expect(
        AgentRolePrompts.runChipLabel('portfolioGuide'),
        'Review portfolio',
      );
      expect(
        AgentRolePrompts.runChipLabel('marketResearch'),
        'Market research',
      );
      expect(
        AgentRolePrompts.runUserPromptDraft(roleId: 'marketResearch'),
        allOf(
          contains('Invest interest'),
          contains(AgentRolePrompts.draftSymbolPlaceholder),
        ),
      );
      expect(
        AgentRolePrompts.runUserPromptDraft(
          roleId: 'marketResearch',
          symbol: 'aapl',
        ),
        'Investigate AAPL.',
      );
      expect(
        AgentRolePrompts.runUserPromptDraft(
          roleId: 'intradayTrading',
          symbol: 'msft',
        ),
        allOf(
          contains('MSFT'),
          contains(AgentRolePrompts.draftSidePlaceholder),
          contains(AgentRolePrompts.draftQuantityPlaceholder),
        ),
      );
      expect(
        AgentRolePrompts.runUserPromptDraft(roleId: 'intradayTrading'),
        allOf(
          contains('Invest interest charts'),
          contains(AgentRolePrompts.draftSymbolPlaceholder),
          isNot(contains(AgentRolePrompts.draftSidePlaceholder)),
          isNot(contains(AgentRolePrompts.draftQuantityPlaceholder)),
        ),
      );
      expect(
        AgentRolePrompts.runUserPromptDraft(roleId: 'portfolioGuide'),
        contains(AgentRolePrompts.draftSymbolPlaceholder),
      );
      expect(AgentRolePrompts.supportsTradeProposals('liveBalanceExplainer'), isFalse);
      expect(AgentRolePrompts.usesLiveBalanceContext('liveBalanceExplainer'), isTrue);
      expect(AgentRolePrompts.usesLiveBalanceContext('portfolioGuide'), isTrue);
      expect(AgentRolePrompts.usesPracticePortfolioContext('portfolioGuide'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('liveBalanceExplainer'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('portfolioGuide'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('marketResearch'), isTrue);
      expect(AgentRolePrompts.allowsRunWithoutSymbol('intradayTrading'), isTrue);
    });

    test('flags unresolved draft placeholders', () {
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'marketResearch',
          text:
              'Suggest investment ideas. Optional focus: SYMBOL '
              '(or delete that sentence).',
        ),
        isNull,
      );
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'portfolioGuide',
          text: 'Review my portfolio. Focus on SYMBOL (or delete this sentence).',
        ),
        isNull,
      );
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'intradayTrading',
          text:
              'Trade check: scan Invest interest charts. '
              'Optional focus: SYMBOL (or delete that sentence).',
        ),
        isNull,
      );
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'intradayTrading',
          text: 'Trade check for AAPL. Side: buy|sell. Quantity: 1.',
        ),
        contains('buy|sell'),
      );
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'intradayTrading',
          text: 'Trade check for AAPL. Side: buy. Quantity: QUANTITY.',
        ),
        contains('QUANTITY'),
      );
      expect(
        AgentRolePrompts.unresolvedDraftPlaceholderMessage(
          roleId: 'intradayTrading',
          text: 'Trade check for AAPL. Side: buy. Quantity: 2.',
        ),
        isNull,
      );
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

  group('AgentChatController sendStarter content', () {
    test('content override persists short Run message', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();
      final tradeExecutor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );
      final harness = await buildAgentChatController(
        store: store,
        agents: agents,
        chats: chats,
        marketData: market,
        tradeExecutor: tradeExecutor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
        reply: 'Short research reply.',
      );

      final result = await harness.controller.sendStarter(
        roleId: 'marketResearch',
        content: 'Investigate MSFT.',
      );
      expect(result, isA<AgentChatSendOk>());
      final messages = chats.threadFor(harness.chatId).messages;
      expect(messages, isNotEmpty);
      final user = messages.first;
      expect(user.role, AgentChatRole.user);
      expect(user.kind, AgentChatMessageKind.run);
      expect(user.content, contains('Investigate MSFT.'));
      expect(user.content, contains('Market snapshot'));
    });

    test('allows Market Research discovery Run without a ticker', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();
      final tradeExecutor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );
      final harness = await buildAgentChatController(
        store: store,
        agents: agents,
        chats: chats,
        marketData: market,
        tradeExecutor: tradeExecutor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
        reply: 'Here are a few ideas for Invest interest.',
      );

      final content = AgentRolePrompts.runUserPromptDraft(
        roleId: 'marketResearch',
      );
      final result = await harness.controller.sendStarter(
        roleId: 'marketResearch',
        content: content,
      );
      expect(result, isA<AgentChatSendOk>());
      final messages = chats.threadFor(harness.chatId).messages;
      expect(messages, isNotEmpty);
      expect(messages.first.content, content);
    });

    test('allows Trade check Invest interest scan without a ticker', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();
      final tradeExecutor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );
      final harness = await buildAgentChatController(
        store: store,
        agents: agents,
        chats: chats,
        marketData: market,
        tradeExecutor: tradeExecutor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
        reply: 'No setup in Invest interest; asking research for ideas.',
      );

      final content = AgentRolePrompts.runUserPrompt(
        roleId: 'intradayTrading',
        symbol: '',
      );
      final result = await harness.controller.sendStarter(
        roleId: 'intradayTrading',
        content: content,
      );
      expect(result, isA<AgentChatSendOk>());
      final messages = chats.threadFor(harness.chatId).messages;
      expect(messages, isNotEmpty);
      expect(messages.first.content, content);
    });

    test('rejects Trade check with unresolved side placeholder', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();
      final tradeExecutor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );
      final harness = await buildAgentChatController(
        store: store,
        agents: agents,
        chats: chats,
        marketData: market,
        tradeExecutor: tradeExecutor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
      );

      final result = await harness.controller.sendStarter(
        roleId: 'intradayTrading',
        content: 'Trade check for AAPL. Side: buy|sell. Quantity: 1.',
      );
      expect(result, isA<AgentChatSendFailed>());
      expect(chats.threadFor(harness.chatId).messages, isEmpty);
    });
  });

  group('AgentChatMessage generation meta', () {
    test('formats duration and joins specialty · model · time', () {
      expect(AgentChatMessage.formatGenerationDuration(842), '842ms');
      expect(AgentChatMessage.formatGenerationDuration(1200), '1.2s');
      expect(AgentChatMessage.formatGenerationDuration(10500), '11s');
      expect(AgentChatMessage.formatGenerationDuration(65000), '1m 5s');

      final sentAt = DateTime.utc(2026, 1, 1, 12);
      final whenLabel = formatRelativeTime(sentAt);
      final labeled = AgentChatMessage(
        id: 'a1',
        role: AgentChatRole.assistant,
        content: 'Hello',
        createdAt: sentAt,
        modelId: 'gemini-2.0-flash',
        generationMs: 1200,
        specialtyRoleIds: const ['marketResearch'],
      );
      expect(
        labeled.generationMetaLabel,
        'Market Research · gemini-2.0-flash · 1.2s · $whenLabel',
      );
      expect(
        AgentChatMessage(
          id: 'a2',
          role: AgentChatRole.assistant,
          content: 'Hi',
          createdAt: sentAt,
          modelId: 'gemini-2.0-flash',
          generationMs: 1200,
        ).generationMetaLabel,
        'gemini-2.0-flash · 1.2s · $whenLabel',
      );
      expect(
        AgentChatMessage(
          id: 'a3',
          role: AgentChatRole.assistant,
          content: 'Hi',
          createdAt: DateTime.utc(2026, 1, 1),
        ).generationMetaLabel,
        isNull,
      );
    });
  });
}
