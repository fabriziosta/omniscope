import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../widgets/app_text.dart';
import '../../widgets/app_tooltip.dart';

/// Sidebar destinations for Settings. Only one body is mounted at a time.
enum SettingsNavSection {
  appearance,
  mandate,
  dataSources,
  portfolios,
  connections,
  agents,
  dataAndPrivacy,
}

/// One scroll target / sidebar row under a [SettingsNavSection].
class SettingsNavSubsection {
  const SettingsNavSubsection({required this.id, required this.title});

  final String id;
  final String title;
}

extension SettingsNavSectionX on SettingsNavSection {
  String get title => switch (this) {
        SettingsNavSection.appearance => 'Appearance',
        SettingsNavSection.mandate => 'Mandate',
        SettingsNavSection.dataSources => 'Data sources',
        SettingsNavSection.portfolios => 'Portfolios',
        SettingsNavSection.connections => 'Connections',
        SettingsNavSection.agents => 'Agents',
        SettingsNavSection.dataAndPrivacy => 'Data & privacy',
      };

  String get subtitle => switch (this) {
        SettingsNavSection.appearance =>
          'Brightness, color set, lists, numbers, charts',
        SettingsNavSection.mandate =>
          'Goal, universe, and risk rails for agents',
        SettingsNavSection.dataSources =>
          'Market providers, crypto venues, credentials',
        SettingsNavSection.portfolios =>
          'Practice cash and live connections',
        SettingsNavSection.connections =>
          'LLM keys, models, and exchange credentials',
        SettingsNavSection.agents =>
          'Answer mood, specialties, Autopilot, and schedule',
        SettingsNavSection.dataAndPrivacy =>
          'Config path, backup, and clear local data',
      };

  IconData get icon => switch (this) {
        SettingsNavSection.appearance => LucideIcons.palette,
        SettingsNavSection.mandate => LucideIcons.crosshair,
        SettingsNavSection.dataSources => LucideIcons.database,
        SettingsNavSection.portfolios => LucideIcons.wallet,
        SettingsNavSection.connections => LucideIcons.plug,
        SettingsNavSection.agents => LucideIcons.sparkles,
        SettingsNavSection.dataAndPrivacy => LucideIcons.shield,
      };

  /// Sidebar + scroll-anchor catalog. Ids are stable; titles match body labels.
  List<SettingsNavSubsection> get subsections => switch (this) {
        SettingsNavSection.appearance => const [
            SettingsNavSubsection(id: 'brightness', title: 'Brightness'),
            SettingsNavSubsection(id: 'colorSet', title: 'Color set'),
            SettingsNavSubsection(id: 'lists', title: 'Lists'),
            SettingsNavSubsection(id: 'numbers', title: 'Numbers'),
            SettingsNavSubsection(id: 'charts', title: 'Charts'),
          ],
        SettingsNavSection.mandate => const [
            SettingsNavSubsection(id: 'goal', title: 'Goal'),
            SettingsNavSubsection(id: 'horizon', title: 'Horizon'),
            SettingsNavSubsection(id: 'universe', title: 'Universe'),
            SettingsNavSubsection(id: 'cadence', title: 'Preferred cadence'),
            SettingsNavSubsection(id: 'riskRails', title: 'Risk rails'),
          ],
        SettingsNavSection.dataSources => const [
            SettingsNavSubsection(
              id: 'marketProviders',
              title: 'Market providers',
            ),
            SettingsNavSubsection(id: 'cryptoVenues', title: 'Crypto venues'),
            SettingsNavSubsection(id: 'brokers', title: 'Brokers'),
            SettingsNavSubsection(id: 'credentials', title: 'Credentials'),
          ],
        SettingsNavSection.portfolios => const [
            SettingsNavSubsection(id: 'startingCash', title: 'Starting cash'),
            SettingsNavSubsection(
              id: 'resetPractice',
              title: 'Reset practice holdings',
            ),
            SettingsNavSubsection(
              id: 'livePortfolios',
              title: 'Live portfolios',
            ),
          ],
        SettingsNavSection.connections => const [
            SettingsNavSubsection(
              id: 'llmKeys',
              title: 'LLM API keys & models',
            ),
            SettingsNavSubsection(
              id: 'exchangeCredentials',
              title: 'Exchange credentials',
            ),
          ],
        SettingsNavSection.agents => const [
            SettingsNavSubsection(id: 'sharedMemory', title: 'Shared memory'),
            SettingsNavSubsection(id: 'answerMood', title: 'Answer mood'),
            SettingsNavSubsection(
              id: 'specialties',
              title: 'Enabled specialties',
            ),
            SettingsNavSubsection(
              id: 'autopilotPortfolio',
              title: 'Autopilot portfolio',
            ),
            SettingsNavSubsection(id: 'schedule', title: 'Schedule'),
          ],
        SettingsNavSection.dataAndPrivacy => const [
            SettingsNavSubsection(
              id: 'dataFile',
              title: 'Data file location',
            ),
            SettingsNavSubsection(id: 'backup', title: 'Backup'),
            SettingsNavSubsection(id: 'favorites', title: 'Favorites'),
            SettingsNavSubsection(
              id: 'investInterest',
              title: 'Invest interest',
            ),
            SettingsNavSubsection(id: 'sharedMemory', title: 'Shared memory'),
            SettingsNavSubsection(id: 'agentChats', title: 'Agent chats'),
            SettingsNavSubsection(id: 'tradeActivity', title: 'Trade activity'),
            SettingsNavSubsection(id: 'llmAgents', title: 'LLM & agents'),
            SettingsNavSubsection(
              id: 'practiceHoldings',
              title: 'Practice holdings',
            ),
            SettingsNavSubsection(
              id: 'exchangeCredentials',
              title: 'Exchange credentials',
            ),
          ],
      };

  static SettingsNavSection? tryParse(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in SettingsNavSection.values) {
      if (s.name == id) return s;
    }
    return null;
  }
}

/// Expandable Settings sidebar group: section header + indented subsections.
class SettingsNavExpandableGroup extends StatelessWidget {
  const SettingsNavExpandableGroup({
    super.key,
    required this.section,
    required this.expanded,
    required this.selected,
    required this.focusedSubsectionId,
    required this.onHeaderTap,
    required this.onSubsectionTap,
  });

  final SettingsNavSection section;
  final bool expanded;
  final bool selected;
  final String? focusedSubsectionId;
  final VoidCallback onHeaderTap;
  final ValueChanged<SettingsNavSubsection> onSubsectionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsNavSectionHeader(
          title: section.title,
          icon: section.icon,
          selected: selected,
          expanded: expanded,
          onTap: onHeaderTap,
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          for (final sub in section.subsections) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: SettingsNavSubsectionTile(
                title: sub.title,
                selected: selected && focusedSubsectionId == sub.id,
                onTap: () => onSubsectionTap(sub),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }
}

class _SettingsNavSectionHeader extends StatelessWidget {
  const _SettingsNavSectionHeader({
    required this.title,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    return AppTooltip(
      message: title,
      wrapDetector: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.secondary : null,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.border,
                ),
                borderRadius: theme.radius,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                                .withValues(alpha: 0.12)
                            : theme.colorScheme.secondary,
                        borderRadius: theme.radius,
                      ),
                      child: Icon(
                        icon,
                        size: 13,
                        color: selected
                            ? theme.colorScheme.secondaryForeground
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppEllipsisText(
                        title,
                        maxLines: 2,
                        style: theme.textTheme.p.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Transform.rotate(
                      angle: expanded ? 0 : -math.pi / 2,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indented subsection row under an expanded Settings section header.
class SettingsNavSubsectionTile extends StatelessWidget {
  const SettingsNavSubsectionTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;
    final muted = selected
        ? theme.colorScheme.secondaryForeground.withValues(alpha: 0.8)
        : theme.colorScheme.mutedForeground;

    return AppTooltip(
      message: title,
      wrapDetector: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.secondary : null,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.border.withValues(alpha: 0.6),
                ),
                borderRadius: theme.radius,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: AppEllipsisText(
                        title,
                        maxLines: 2,
                        style: theme.textTheme.small.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 12,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
