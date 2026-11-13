import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_chat_client.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multiple connected agents shows picker', (tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    for (final id in ['marketResearch', 'hedgeFundDesk']) {
      await agents.connect(
        roleId: id,
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk-test',
        modelId: 'gpt-6-luna',
      );
    }
    final agentChats = AgentChatRepository(store: store);
    await agentChats.load();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MarketDataClient>.value(
            value: FakeMarketDataClient(
              emptyQuotes: true,
              emptyHistory: true,
            ),
          ),
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<AgentChatRepository>.value(value: agentChats),
          Provider<LlmChatClient>.value(
            value: LlmChatClient(
              httpClient: MockClient(
                (_) async => http.Response('{}', 400),
              ),
            ),
          ),
          ChangeNotifierProvider<ShellNavigationController>(
            create: (_) => ShellNavigationController(),
          ),
        ],
        child: ShadApp(
          home: Builder(
            builder: (context) {
              return ColoredBox(
                color: BrandColors.lightScheme().background,
                child: Center(
                  child: ShadButton(
                    onPressed: () {
                      AgentLaunchActions.launch(
                        context,
                        intent: AgentLaunchIntent.investigate,
                        symbol: 'MSFT',
                      );
                    },
                    child: const Text('Go'),
                  ),
                ),
              );
            },
          ),
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: BrandColors.lightScheme(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Investigate with'), findsOneWidget);
    expect(find.text('Market Research & Analysis'), findsOneWidget);
    expect(find.text('Hedge Fund Desk'), findsOneWidget);
  });
}
