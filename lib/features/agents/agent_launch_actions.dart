import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/fade_page_route.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/models.dart';
import '../../widgets/app_toast.dart';
import 'agent_chat_screen.dart';

/// Shared navigation + picker for opening agent chat from any screen.
class AgentLaunchActions {
  AgentLaunchActions._();

  /// Push chat for [role], optionally auto-running a symbol turn.
  static Future<void> openAgentChat(
    BuildContext context, {
    required AgentRoleDefinition role,
    String? initialSymbol,
    bool autoRun = false,
    String? side,
    double? quantity,
  }) {
    return pushFadePage<void>(
      context,
      AgentChatScreen(
        role: role,
        initialSymbol: initialSymbol,
        autoRun: autoRun,
        initialSide: side,
        initialQuantity: quantity,
      ),
    );
  }

  /// Resolve applicable roles for [intent] and launch or show a picker.
  ///
  /// - One connected role → open chat (auto-run when [symbol] is set).
  /// - Several connected → dialog to choose.
  /// - None connected → Agents tab + Connect dialog for the preferred role.
  static Future<void> launch(
    BuildContext context, {
    required AgentLaunchIntent intent,
    required String symbol,
    String? side,
    double? quantity,
  }) async {
    final agents = context.read<AgentsRepository>();
    final applicable = AgentLaunchResolver.rolesForIntent(
      availableRoles: agents.availableRoles,
      intent: intent,
    );
    if (applicable.isEmpty) {
      showAppToast(
        context,
        description: 'No agent is available for this action yet.',
        destructive: true,
      );
      context.read<ShellNavigationController>().goToAgents();
      return;
    }

    final connected = AgentLaunchResolver.connectedAmong(
      roles: applicable,
      isConnected: (id) => agents.forRoleId(id).connected,
    );

    if (connected.isEmpty) {
      final preferred = applicable.first;
      showAppToast(
        context,
        title: 'Connect an agent',
        description:
            'Connect ${preferred.title} to use this action, then try again.',
      );
      context.read<ShellNavigationController>().goToAgents(
            connectRoleId: preferred.id,
          );
      return;
    }

    if (connected.length == 1) {
      await openAgentChat(
        context,
        role: connected.first,
        initialSymbol: symbol,
        autoRun: true,
        side: side,
        quantity: quantity,
      );
      return;
    }

    final chosen = await showShadDialog<AgentRoleDefinition>(
      context: context,
      builder: (context) => _AgentLaunchPickerDialog(
        title: intent.pickerTitle,
        symbol: symbol.trim().toUpperCase(),
        roles: connected,
      ),
    );
    if (chosen == null || !context.mounted) return;
    await openAgentChat(
      context,
      role: chosen,
      initialSymbol: symbol,
      autoRun: true,
      side: side,
      quantity: quantity,
    );
  }
}

class _AgentLaunchPickerDialog extends StatelessWidget {
  const _AgentLaunchPickerDialog({
    required this.title,
    required this.symbol,
    required this.roles,
  });

  final String title;
  final String symbol;
  final List<AgentRoleDefinition> roles;

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(title),
      description: Text(
        'Choose an agent for $symbol. Chat opens with a Run for this symbol.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < roles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _AgentLaunchRoleTile(
                role: roles[i],
                onTap: () => Navigator.of(context).pop(roles[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentLaunchRoleTile extends StatelessWidget {
  const _AgentLaunchRoleTile({
    required this.role,
    required this.onTap,
  });

  final AgentRoleDefinition role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.title, style: theme.textTheme.large),
                const SizedBox(height: 2),
                Text(
                  role.description,
                  style: theme.textTheme.muted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
