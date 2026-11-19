import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_screen.dart';
import 'package:omniscope/features/agents/agents_screen.dart';
import 'package:omniscope/widgets/master_detail_shell.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

Future<({AgentChatRepository chats, ShellNavigationController shellNav})>
    _pumpAgents({
  required WidgetTester tester,
  required Size surfaceSize,
  ShellNavigationController? shellNav,
}) async {
  // Real async I/O must run outside FakeAsync — a prior AgentsScreen can leave
  // a ShadInput caret timer running, which would hang bare `await`s here.
  final setup = await tester.runAsync(() async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    final seeded = await seedLlmStack(
      store,
      lightModelId: 'gpt-test',
      heavyModelId: 'gpt-test',
    );
    final agentChats = AgentChatRepository(store: store);
    await agentChats.load();
    final proposals = TradeProposalRepository(store: store);
    await proposals.load();
    final activity = AgentActivityRepository(store: store);
    await activity.load();
    final investInterest = InvestInterestProposalRepository(store: store);
    await investInterest.load();
    final dataSources = DataSourceSettings(store: store);
    await dataSources.load();
    final portfolio = PortfolioRepository(store: store);
    await portfolio.load();
    final favorites = FavoritesRepository(store: store);
    await favorites.load();
    final mandate = MandateSettings(store: store);
    await mandate.load();
    return (
      agents: agents,
      seeded: seeded,
      agentChats: agentChats,
      proposals: proposals,
      activity: activity,
      investInterest: investInterest,
      dataSources: dataSources,
      portfolio: portfolio,
      favorites: favorites,
      mandate: mandate,
    );
  });
  if (setup == null) {
    throw StateError('agents sidebar test setup failed');
  }

  final marketData = FakeMarketDataClient(emptyQuotes: true, emptyHistory: true);
  const cryptoRegistry = CryptoExchangeRegistry([]);
  const brokerRegistry = BrokerExchangeRegistry.empty;
  final tradeExecutor = RoutingTradeExecutor(
    cryptoRegistry: cryptoRegistry,
    brokerRegistry: brokerRegistry,
    dataSources: setup.dataSources,
    portfolio: setup.portfolio,
    marketData: marketData,
  );
  final nav = shellNav ?? ShellNavigationController();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() async {
    // Drop the tree so caret / animation tickers do not leak into the next test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<MarketDataClient>.value(value: marketData),
        Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
        Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
        Provider<TradeExecutor>.value(value: tradeExecutor),
        ChangeNotifierProvider<DataSourceSettings>.value(
          value: setup.dataSources,
        ),
        ChangeNotifierProvider<PortfolioRepository>.value(
          value: setup.portfolio,
        ),
        ChangeNotifierProvider<FavoritesRepository>.value(
          value: setup.favorites,
        ),
        ChangeNotifierProvider<MandateSettings>.value(value: setup.mandate),
        ChangeNotifierProvider<AgentsRepository>.value(value: setup.agents),
        ChangeNotifierProvider<LlmRuntimeSettings>.value(
          value: setup.seeded.llmRuntime,
        ),
        ChangeNotifierProvider<AgentAppSettings>.value(
          value: setup.seeded.appSettings,
        ),
        ChangeNotifierProvider<AgentChatRepository>.value(
          value: setup.agentChats,
        ),
        ChangeNotifierProvider<TradeProposalRepository>.value(
          value: setup.proposals,
        ),
        ChangeNotifierProvider<AgentActivityRepository>.value(
          value: setup.activity,
        ),
        ChangeNotifierProvider<InvestInterestProposalRepository>.value(
          value: setup.investInterest,
        ),
        ChangeNotifierProvider<EnvSecretsRepository>.value(
          value: setup.seeded.secrets,
        ),
        Provider<GenkitAgentRunner>.value(value: fakeGenkitAgentRunner()),
        ChangeNotifierProvider<ShellNavigationController>.value(value: nav),
      ],
      child: ShadApp(
        home: const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: AgentsScreen(),
        ),
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: BrandColors.lightScheme(),
        ),
      ),
    ),
  );
  await tester.pump();
  return (chats: setup.agentChats, shellNav: nav);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sidebar switches chats and goToAgentChat opens without push',
      (tester) async {
    // --- Wide: switch between threads ---
    final wide = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(900, 844),
    );
    final chats = wide.chats;

    final a = await chats.createChat(title: 'Chat A');
    final b = await chats.createChat(title: 'Chat B');
    await chats.append(
      chatId: a.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'Message from A',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await chats.append(
      chatId: b.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'Message from B',
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await tester.pump();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Message from B'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Message from A'),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(MasterDetailMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat A').first);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Message from A'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Message from B'),
      ),
      findsNothing,
    );

    // --- Narrow: shell deep-link selects a chat ---
    final shellNav = ShellNavigationController();
    final narrow = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(390, 844),
      shellNav: shellNav,
    );

    final other = await narrow.chats.createChat(title: 'Other chat');
    await narrow.chats.append(
      chatId: other.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'Not the pending chat',
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    );
    final thread = await narrow.chats.createChat(title: 'Pending chat');
    await narrow.chats.append(
      chatId: thread.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'Opened from shell',
        createdAt: DateTime.utc(2026, 1, 3),
      ),
    );
    await tester.pump();

    // Content-first: newest/first selected chat is already visible.
    expect(find.byType(AgentChatScreen), findsOneWidget);

    shellNav.goToAgentChat(chatId: thread.chatId);
    await tester.pump();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Opened from shell'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('starter prompts hide after the first user message',
      (tester) async {
    final pumped = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(900, 844),
    );
    final chats = pumped.chats;

    final empty = await chats.createChat(title: 'Fresh thread');
    await tester.pump();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Market research'),
      ),
      findsOneWidget,
    );

    await chats.append(
      chatId: empty.chatId,
      message: AgentChatMessage(
        id: AgentChatMessage.newId(),
        role: AgentChatRole.user,
        content: 'Hello agents',
        createdAt: DateTime.utc(2026, 1, 4),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Hello agents'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AgentChatScreen),
        matching: find.text('Market research'),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping a starter drafts the composer without sending',
      (tester) async {
    final pumped = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(900, 844),
    );
    final chats = pumped.chats;

    await chats.createChat(title: 'Draft thread');
    await tester.pump();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    expect(find.text('Market research'), findsOneWidget);

    await tester.tap(find.text('Market research'));
    await tester.pump();

    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: 'marketResearch',
    );
    expect(find.text(draft), findsWidgets);

    final inputs = tester.widgetList<ShadInput>(find.byType(ShadInput));
    final composer = inputs.cast<ShadInput?>().firstWhere(
          (input) => input?.controller?.text == draft,
          orElse: () => null,
        );
    expect(composer, isNotNull);
    expect(composer!.controller!.text, draft);

    final thread = chats.threads.firstWhere((t) => t.title == 'Draft thread');
    expect(thread.messages, isEmpty);
  });

  testWidgets(
      'goToAgentChat with starter drafts composer and does not auto-send',
      (tester) async {
    final shellNav = ShellNavigationController();
    final pumped = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(390, 844),
      shellNav: shellNav,
    );

    final thread = await pumped.chats.createChat(title: 'Launch draft');
    await tester.pump();

    shellNav.goToAgentChat(
      chatId: thread.chatId,
      starterRoleId: 'marketResearch',
      symbol: 'AAPL',
      autoRun: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: 'marketResearch',
      symbol: 'AAPL',
    );
    expect(find.byType(AgentChatScreen), findsOneWidget);
    final inputs = tester.widgetList<ShadInput>(find.byType(ShadInput));
    final composer = inputs.cast<ShadInput?>().firstWhere(
          (input) => input?.controller?.text == draft,
          orElse: () => null,
        );
    expect(composer, isNotNull);
    expect(composer!.controller!.text, draft);
    expect(pumped.chats.threadFor(thread.chatId).messages, isEmpty);
  });

  testWidgets(
      'sending a selected starter persists a short Run message',
      (tester) async {
    final shellNav = ShellNavigationController();
    final pumped = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(390, 844),
      shellNav: shellNav,
    );

    final thread = await pumped.chats.createChat(title: 'Run send');
    await tester.pump();

    shellNav.goToAgentChat(
      chatId: thread.chatId,
      starterRoleId: 'marketResearch',
      symbol: 'AAPL',
      autoRun: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: 'marketResearch',
      symbol: 'AAPL',
    );
    expect(draft, 'Investigate AAPL.');

    await tester.tap(find.text('Send'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final messages = pumped.chats.threadFor(thread.chatId).messages;
    expect(messages, isNotEmpty);
    final user = messages.firstWhere((m) => m.role == AgentChatRole.user);
    expect(user.kind, AgentChatMessageKind.run);
    expect(user.content, 'Investigate AAPL.');
  });

  testWidgets(
      'goToAgentChat portfolio guide drafts without sending',
      (tester) async {
    final shellNav = ShellNavigationController();
    final pumped = await _pumpAgents(
      tester: tester,
      surfaceSize: const Size(390, 844),
      shellNav: shellNav,
    );

    final thread = await pumped.chats.createChat(title: 'Portfolio draft');
    await tester.pump();

    shellNav.goToAgentChat(
      chatId: thread.chatId,
      starterRoleId: 'portfolioGuide',
      autoRun: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final draft = AgentRolePrompts.runUserPromptDraft(
      roleId: 'portfolioGuide',
    );
    final inputs = tester.widgetList<ShadInput>(find.byType(ShadInput));
    final composer = inputs.cast<ShadInput?>().firstWhere(
          (input) => input?.controller?.text == draft,
          orElse: () => null,
        );
    expect(composer, isNotNull);
    expect(pumped.chats.threadFor(thread.chatId).messages, isEmpty);
  });
}
