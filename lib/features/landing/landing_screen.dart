import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/app_info.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/market/models.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_placeholder_icon.dart';
import '../agents/agent_launch_actions.dart';

/// Cold-start / brand-tap Home surface (welcome hero + tab shortcuts).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const _shortcuts = <(int, String, String, IconData)>[
    (
      ShellNavigationController.marketsTabIndex,
      'Markets',
      AppCopy.tabTooltipMarkets,
      LucideIcons.lineChart,
    ),
    (
      ShellNavigationController.portfolioTabIndex,
      'Portfolio',
      AppCopy.tabTooltipPortfolio,
      LucideIcons.wallet,
    ),
    (
      ShellNavigationController.activityTabIndex,
      'Activity',
      AppCopy.tabTooltipActivity,
      LucideIcons.activity,
    ),
    (
      ShellNavigationController.agentsTabIndex,
      'Agents',
      AppCopy.tabTooltipAgents,
      LucideIcons.bot,
    ),
    (
      ShellNavigationController.settingsTabIndex,
      'Settings',
      AppCopy.tabTooltipSettings,
      LucideIcons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final secrets = context.watch<EnvSecretsRepository>();
    final runtime = context.watch<LlmRuntimeSettings>();
    final hasLlm = LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    );
    final sampleSymbol =
        defaultWatchlist.isNotEmpty ? defaultWatchlist.first : 'AAPL';

    return ColoredBox(
      color: scheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.secondary.withValues(alpha: 0.55),
                          scheme.background,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                      child: Column(
                        children: [
                          const AppPlaceholderIcon(size: 64),
                          const SizedBox(height: 16),
                          Text(
                            AppInfo.name,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.h3.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.foreground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppCopy.tagline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.large.copyWith(
                              color: scheme.foreground,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            AppCopy.landingSupport,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _shortcuts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _LandingShortcut(
                      label: _shortcuts[i].$2,
                      description: _shortcuts[i].$3,
                      icon: _shortcuts[i].$4,
                      onPressed: () => context
                          .read<ShellNavigationController>()
                          .selectTab(_shortcuts[i].$1),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (hasLlm)
                    ShadButton.outline(
                      onPressed: () {
                        AgentLaunchActions.launch(
                          context,
                          intent: AgentLaunchIntent.investigate,
                          symbol: sampleSymbol,
                        );
                      },
                      child: Text(
                        '${AppCopy.landingTryInvestigate} $sampleSymbol',
                      ),
                    )
                  else
                    ShadButton.ghost(
                      onPressed: () {
                        context
                            .read<ShellNavigationController>()
                            .goToSettings(sectionId: 'connections');
                      },
                      child: const Text(AppCopy.landingOpenConnections),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    AppCopy.delayedDataCaption,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.small.copyWith(
                      color: scheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppCopy.landingDisclaimer,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.small.copyWith(
                      color: scheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LandingShortcut extends StatelessWidget {
  const _LandingShortcut({
    required this.label,
    required this.description,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.border),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.p.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.foreground,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.small.copyWith(
                            color: scheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: scheme.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
