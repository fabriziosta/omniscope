import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/brand_colors.dart';
import 'package:omniscope/core/shell_navigation.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_launch.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/features/agents/agent_launch_actions.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launch without LLM key redirects to Settings connections',
      (tester) async {
    final store = await memoryConfig();
    final agentRoles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: agentRoles);
    await agents.load(roleCatalog: agentRoles);
    final llmRuntime = LlmRuntimeSettings(store: store);
    await llmRuntime.load();
    final agentApp = AgentAppSettings(store: store);
    await agentApp.load();
    final secrets = EnvSecretsRepository(store: store, syncEnvFile: false);
    await secrets.load();
    final shellNav = ShellNavigationController();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AgentsRepository>.value(value: agents),
          ChangeNotifierProvider<LlmRuntimeSettings>.value(value: llmRuntime),
          ChangeNotifierProvider<AgentAppSettings>.value(value: agentApp),
          ChangeNotifierProvider<EnvSecretsRepository>.value(value: secrets),
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

    expect(shellNav.tabIndex, ShellNavigationController.settingsTabIndex);
    expect(shellNav.pendingSettingsSectionId, 'connections');
  });
}
