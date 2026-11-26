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
import 'portfolios_section.dart';
import 'settings_nav.dart';

export 'settings_nav.dart' show SettingsNavSection, SettingsNavSubsection;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsNavSection _selected = SettingsNavSection.appearance;
  late final Set<SettingsNavSection> _expanded = {_selected};
  String? _focusedSubsectionId;

  final ScrollController _contentScroll = ScrollController();
  final Map<String, GlobalKey> _subsectionKeys = {};

  ShellNavigationController? _shellNav;

  GlobalKey _keyFor(SettingsNavSection section, String subsectionId) {
    final id = '${section.name}.$subsectionId';
    return _subsectionKeys.putIfAbsent(id, GlobalKey.new);
  }

  Map<String, GlobalKey> _keysFor(SettingsNavSection section) {
    return {
      for (final sub in section.subsections)
        sub.id: _keyFor(section, sub.id),
    };
  }

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
    _contentScroll.dispose();
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
    // Legacy ids from before Data file + Privacy & data were merged, and
    // before Connections folded into Agents.
    if (raw == 'dataFile' || raw == 'privacy') {
      section = SettingsNavSection.dataAndPrivacy;
    } else if (raw == 'connections') {
      section = SettingsNavSection.agents;
    } else {
      section = SettingsNavSectionX.tryParse(raw);
    }
    if (section == null) return;
    _select(section);
  }

  void _select(SettingsNavSection section, {String? subsectionId}) {
    setState(() {
      _selected = section;
      _expanded.add(section);
      _focusedSubsectionId = subsectionId;
    });

    if (subsectionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSubsection(section, subsectionId);
      });
    } else if (_contentScroll.hasClients) {
      _contentScroll.jumpTo(0);
    }
  }

  void _onHeaderTap(SettingsNavSection section) {
    final wasSelected = _selected == section;
    final wasExpanded = _expanded.contains(section);
    setState(() {
      _selected = section;
      _focusedSubsectionId = null;
      if (wasSelected && wasExpanded) {
        _expanded.remove(section);
      } else {
        _expanded.add(section);
      }
    });
    if (_contentScroll.hasClients) {
      _contentScroll.jumpTo(0);
    }
  }

  void _onSubsectionTap(
    SettingsNavSection section,
    SettingsNavSubsection sub, {
    required VoidCallback closeNav,
  }) {
    _select(section, subsectionId: sub.id);
    closeNav();
  }

  void _scrollToSubsection(SettingsNavSection section, String subsectionId) {
    if (!mounted) return;
    final key = _keyFor(section, subsectionId);
    final ctx = key.currentContext;
    if (ctx == null) {
      // Body may still be mounting after a section switch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = key.currentContext;
        if (retry == null) return;
        Scrollable.ensureVisible(
          retry,
          alignment: 0.05,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.05,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _bodyFor(SettingsNavSection section) {
    final keys = _keysFor(section);
    return switch (section) {
      SettingsNavSection.appearance => AppearanceSectionBody(
          subsectionKeys: keys,
        ),
      SettingsNavSection.dataSources => DataSourcesSectionBody(
          subsectionKeys: keys,
        ),
      SettingsNavSection.portfolios => PortfoliosSectionBody(
          subsectionKeys: keys,
          onOpenDataSources: () => _select(SettingsNavSection.dataSources),
        ),
      SettingsNavSection.agents => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionsSectionBody(subsectionKeys: keys),
            const SizedBox(height: 28),
            AgentsAdvancedSectionBody(subsectionKeys: keys),
          ],
        ),
      SettingsNavSection.dataAndPrivacy => DataPrivacySectionBody(
          subsectionKeys: keys,
        ),
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
              SettingsNavExpandableGroup(
                section: section,
                expanded: _expanded.contains(section),
                selected: highlighted == section,
                focusedSubsectionId:
                    highlighted == section ? _focusedSubsectionId : null,
                onHeaderTap: () => _onHeaderTap(section),
                onSubsectionTap: (sub) => _onSubsectionTap(
                  section,
                  sub,
                  closeNav: closeNav,
                ),
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
            controller: _contentScroll,
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
