import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/shell_navigation.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_toast.dart';

/// Shared navigation for opening orchestrator chat from any screen.
class AgentLaunchActions {
  AgentLaunchActions._();

  /// Create/open a chat on the Agents tab (master–detail), optionally auto-run.
  static Future<void> openAgentChat(
    BuildContext context, {
    String? chatId,
    String? starterRoleId,
    String? initialSymbol,
    String? initialExchangeId,
    bool autoRun = false,
    String? side,
    double? quantity,
  }) async {
    final chats = context.read<AgentChatRepository>();
    final id = chatId ??
        (await chats.createChat(
          title: initialSymbol?.trim().isNotEmpty == true
              ? initialSymbol!.trim()
              : null,
        ))
            .chatId;
    if (!context.mounted) return;
    context.read<ShellNavigationController>().goToAgentChat(
          chatId: id,
          starterRoleId: starterRoleId,
          symbol: initialSymbol,
          initialExchangeId: initialExchangeId,
          autoRun: autoRun,
          initialSide: side,
          initialQuantity: quantity,
        );
  }

  /// Resolve intent → starter role and open orchestrator chat.
  static Future<void> launch(
    BuildContext context, {
    required AgentLaunchIntent intent,
    String? symbol,
    String? exchangeId,
    String? side,
    double? quantity,
  }) async {
    final secrets = context.read<EnvSecretsRepository>();
    final runtime = context.read<LlmRuntimeSettings>();
    if (!LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    )) {
      showAppToast(
        context,
        title: 'Add an LLM key',
        description:
            'Add a provider under Settings → Connections, then try again.',
      );
      context.read<ShellNavigationController>().goToSettings(
            sectionId: 'connections',
          );
      return;
    }

    final agents = context.read<AgentsRepository>();
    final appSettings = context.read<AgentAppSettings>();
    final applicable = AgentLaunchResolver.rolesForIntent(
      availableRoles: agents.availableRoles,
      intent: intent,
    );
    final enabled = [
      for (final r in applicable)
        if (appSettings.isRoleEnabled(r.id)) r,
    ];
    if (enabled.isEmpty) {
      showAppToast(
        context,
        description: 'No agent is available for this action yet.',
        destructive: true,
      );
      context.read<ShellNavigationController>().goToAgents();
      return;
    }

    final preferred = enabled.first;
    final sym = symbol?.trim();
    final shouldAutoRun = intent.isPortfolioLevel
        ? true
        : (sym != null && sym.isNotEmpty);

    await openAgentChat(
      context,
      starterRoleId: preferred.id,
      initialSymbol: sym,
      initialExchangeId: exchangeId,
      autoRun: shouldAutoRun,
      side: side,
      quantity: quantity,
    );
  }
}
