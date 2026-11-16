import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
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
  final marketData = FakeMarketDataClient(emptyQuotes: true, emptyHistory: true);
  const cryptoRegistry = CryptoExchangeRegistry([]);
  const brokerRegistry = BrokerExchangeRegistry.empty;
  final tradeExecutor = RoutingTradeExecutor(
    cryptoRegistry: cryptoRegistry,
    brokerRegistry: brokerRegistry,
    dataSources: dataSources,
    portfolio: portfolio,
    marketData: marketData,
  );
  final nav = shellNav ?? ShellNavigationController();

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<MarketDataClient>.value(value: marketData),
        Provider<CryptoExchangeRegistry>.value(value: cryptoRegistry),
        Provider<BrokerExchangeRegistry>.value(value: brokerRegistry),
        Provider<TradeExecutor>.value(value: tradeExecutor),
        ChangeNotifierProvider<DataSourceSettings>.value(value: dataSources),
        ChangeNotifierProvider<PortfolioRepository>.value(value: portfolio),
        ChangeNotifierProvider<FavoritesRepository>.value(value: favorites),
        ChangeNotifierProvider<MandateSettings>.value(value: mandate),
        ChangeNotifierProvider<AgentsRepository>.value(value: agents),
        ChangeNotifierProvider<LlmRuntimeSettings>.value(
          value: seeded.llmRuntime,
        ),
        ChangeNotifierProvider<AgentAppSettings>.value(
          value: seeded.appSettings,
        ),
        ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
        ChangeNotifierProvider<TradeProposalRepository>.value(value: proposals),
        ChangeNotifierProvider<AgentActivityRepository>.value(value: activity),
        ChangeNotifierProvider<InvestInterestProposalRepository>.value(
          value: investInterest,
        ),
        ChangeNotifierProvider<EnvSecretsRepository>.value(
          value: seeded.secrets,
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
  return (chats: agentChats, shellNav: nav);
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

    await tester.tap(find.text('Chat A').first);
    await tester.pump();

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

    expect(find.byType(AgentChatScreen), findsNothing);

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
        matching: find.text('Run research'),
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
        matching: find.text('Run research'),
      ),
      findsNothing,
    );
  });
}
