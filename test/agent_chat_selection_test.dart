import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/rendering.dart';
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
import 'package:omniscope/widgets/agent_markdown_body.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat message list uses its own SelectionArea for drag-select',
      (tester) async {
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
    if (setup == null) throw StateError('setup failed');

    final marketData =
        FakeMarketDataClient(emptyQuotes: true, emptyHistory: true);
    const cryptoRegistry = CryptoExchangeRegistry([]);
    const brokerRegistry = BrokerExchangeRegistry.empty;
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: cryptoRegistry,
      brokerRegistry: brokerRegistry,
      dataSources: setup.dataSources,
      portfolio: setup.portfolio,
      marketData: marketData,
    );

    await tester.binding.setSurfaceSize(const Size(900, 844));
    addTearDown(() async {
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
          ChangeNotifierProvider<ShellNavigationController>.value(
            value: ShellNavigationController(),
          ),
        ],
        child: ShadApp(
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: BrandColors.lightScheme(),
          ),
          home: const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: AgentsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    final chat = await setup.agentChats.createChat(title: 'Select me');
    await setup.agentChats.append(
      chatId: chat.chatId,
      message: AgentChatMessage(
        id: 'u1',
        role: AgentChatRole.user,
        content: 'plain selectable user message alpha',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await setup.agentChats.append(
      chatId: chat.chatId,
      message: AgentChatMessage(
        id: 'a1',
        role: AgentChatRole.assistant,
        content: '**bold** assistant markdown reply omega',
        createdAt: DateTime.utc(2026, 1, 1, 0, 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentChatScreen), findsOneWidget);
    // Message list SelectionArea + any route-level one.
    expect(find.byType(SelectionArea), findsWidgets);

    final md = find.byType(AgentMarkdownBody);
    expect(md, findsOneWidget);
    final box = tester.getRect(md);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: box.center);
    await gesture.down(box.centerLeft + const Offset(8, 0));
    await tester.pump();
    await gesture.moveTo(box.centerRight - const Offset(8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    var anySelected = false;
    for (final el in find.byType(RichText).evaluate()) {
      final ro = el.renderObject;
      if (ro is RenderParagraph && ro.selections.isNotEmpty) {
        anySelected = true;
        break;
      }
    }
    expect(anySelected, isTrue, reason: 'markdown reply should be selectable');
  });
}
