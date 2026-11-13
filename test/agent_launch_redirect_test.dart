import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unconnected launch redirects to Agents connect', (tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    final shellNav = ShellNavigationController();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<ShellNavigationController>.value(
            value: shellNav,
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
                        symbol: 'AAPL',
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

    expect(shellNav.tabIndex, ShellNavigationController.agentsTabIndex);
    expect(shellNav.pendingAgentConnectRoleId, 'marketResearch');
  });
}
