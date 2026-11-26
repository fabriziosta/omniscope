import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/models.dart';

/// Selectable starter options for empty chats — tap drafts the composer.
class StarterPromptList extends StatelessWidget {
  const StarterPromptList({
    super.key,
    required this.roles,
    required this.enabled,
    required this.selectedRoleId,
    required this.onSelect,
  });

  final List<AgentRoleDefinition> roles;
  final bool enabled;
  final String? selectedRoleId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth >= 720 ? 520.0 : double.infinity;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a starter',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap a starter, edit if needed, then Send. Market '
                      'research can explore a topic; Trade check needs a '
                      'ticker.',
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < roles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      StarterPromptOption(
                        roleId: roles[i].id,
                        enabled: enabled,
                        selected: selectedRoleId == roles[i].id,
                        onSelect: () => onSelect(roles[i].id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StarterPromptOption extends StatelessWidget {
  const StarterPromptOption({
    super.key,
    required this.roleId,
    required this.enabled,
    required this.selected,
    required this.onSelect,
  });

  final String roleId;
  final bool enabled;
  final bool selected;
  final VoidCallback onSelect;

  IconData get _icon => switch (roleId) {
        'marketResearch' => LucideIcons.search,
        'liveBalanceExplainer' => LucideIcons.wallet,
        'portfolioGuide' => LucideIcons.pieChart,
        'intradayTrading' => LucideIcons.activity,
        'cryptoSpotGuide' => LucideIcons.bitcoin,
        'marketsLiteracy' => LucideIcons.bookOpen,
        _ => LucideIcons.messageSquare,
      };

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = AgentRolePrompts.runChipLabel(roleId);
    final description = AgentRolePrompts.runChipDescription(roleId);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      hint: description,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onSelect : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? theme.colorScheme.secondary : null,
                  borderRadius: theme.radius,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.border,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.secondaryForeground
                                  .withValues(alpha: 0.12)
                              : theme.colorScheme.secondary,
                          borderRadius: theme.radius,
                        ),
                        child: Icon(
                          _icon,
                          size: 14,
                          color: selected
                              ? theme.colorScheme.secondaryForeground
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.p.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              description,
                              style: theme.textTheme.small.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected
                            ? LucideIcons.check
                            : LucideIcons.chevronRight,
                        size: 16,
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                            : theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
