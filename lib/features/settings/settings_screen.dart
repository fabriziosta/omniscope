import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_info.dart';
import '../../core/shell_navigation.dart';
import '../../widgets/master_detail_shell.dart';
import 'agents_advanced_section.dart';
import 'appearance_section.dart';
import 'connections_section.dart';
import 'data_privacy_section.dart';
import 'data_sources_section.dart';
import 'mandate_section.dart';
import 'portfolios_section.dart';

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

  static SettingsNavSection? tryParse(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final s in SettingsNavSection.values) {
      if (s.name == id) return s;
    }
    return null;
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsNavSection _selected = SettingsNavSection.appearance;

  ShellNavigationController? _shellNav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shellNav = context.read<ShellNavigationController>();
    if (!identical(_shellNav, shellNav)) {
      _shellNav?.removeListener(_onShellNavChanged);
      _shellNav = shellNav;
      _shellNav!.addListener(_onShellNavChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenPendingSection();
    });
  }

  @override
  void dispose() {
    _shellNav?.removeListener(_onShellNavChanged);
    super.dispose();
  }

  void _onShellNavChanged() => _maybeOpenPendingSection();

  void _maybeOpenPendingSection() {
    if (!mounted) return;
    final shellNav = _shellNav;
    if (shellNav == null) return;
    if (shellNav.tabIndex != ShellNavigationController.settingsTabIndex) {
      return;
    }
    final raw = shellNav.takePendingSettingsSectionId();
    if (raw == null || raw.isEmpty) return;
    SettingsNavSection? section;
    // Legacy ids from before Data file + Privacy & data were merged.
    if (raw == 'dataFile' || raw == 'privacy') {
      section = SettingsNavSection.dataAndPrivacy;
    } else {
      for (final s in SettingsNavSection.values) {
        if (s.name == raw) {
          section = s;
          break;
        }
      }
    }
    if (section == null) return;
    _select(section);
  }

  void _select(SettingsNavSection section) {
    setState(() => _selected = section);
  }

  Widget _bodyFor(SettingsNavSection section) {
    return switch (section) {
      SettingsNavSection.appearance => const AppearanceSectionBody(),
      SettingsNavSection.mandate => const MandateSectionBody(),
      SettingsNavSection.dataSources => const DataSourcesSectionBody(),
      SettingsNavSection.portfolios => PortfoliosSectionBody(
          onOpenDataSources: () => _select(SettingsNavSection.dataSources),
        ),
      SettingsNavSection.connections => const ConnectionsSectionBody(),
      SettingsNavSection.agents => const AgentsAdvancedSectionBody(),
      SettingsNavSection.dataAndPrivacy => const DataPrivacySectionBody(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return MasterDetailShell<SettingsNavSection>(
      selected: _selected,
      sidebarBuilder: (context, highlighted, {required closeNav}) {
        return MasterDetailNavList(
          tiles: [
            for (final section in SettingsNavSection.values)
              MasterDetailNavTile(
                title: section.title,
                icon: section.icon,
                selected: highlighted == section,
                onTap: () {
                  _select(section);
                  closeNav();
                },
              ),
          ],
          footer: Text(
            'v${AppInfo.version}',
            textAlign: TextAlign.center,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        );
      },
      contentBuilder: (context, section, {required onOpenMenu}) {
        return MasterDetailContentPane(
          key: ValueKey(section),
          title: section.title,
          subtitle: section.subtitle,
          onOpenMenu: onOpenMenu,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
            children: [
              KeyedSubtree(
                key: ValueKey(section),
                child: _bodyFor(section),
              ),
            ],
          ),
        );
      },
    );
  }
}
