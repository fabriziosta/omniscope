import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'package:omniscope/data/agents/market_context_builder.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agents_screen.dart';
import 'package:omniscope/widgets/in_tab_back.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
      );
      expect(text, 'Hello research');
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
    final proposals = TradeProposalRepository(store: store);
    await proposals.load();
    final activity = AgentActivityRepository(store: store);
    await activity.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    const cryptoRegistry = CryptoExchangeRegistry([]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final marketData = _agentMarketData();
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: dataSources,
      portfolio: portfolio,
      marketData: marketData,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(value: marketData),
          Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
          Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
          Provider<TradeExecutor>.value(value: tradeExecutor),
          ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
          ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          ChangeNotifierProvider<TradeProposalRepository>.value(
            value: proposals,
          ),
          ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
          Provider<GenkitAgentRunner>.value(
            value: fakeGenkitAgentRunner(),
          ),
          ChangeNotifierProvider<EnvSecretsRepository>.value(
            value: EnvSecretsRepository(store: store, syncEnvFile: false),
          ),
          ChangeNotifierProvider<ShellNavigationController>(
            create: (_) => ShellNavigationController(),
          ),
        ],
        child: ShadApp(
          home: InTabBackScope(
            registry: InTabBackRegistry(),
            child: const ShellTabIndex(
              index: 3,
              child: AgentsScreen(),
            ),
          ),
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
