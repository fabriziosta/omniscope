import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/tab_page_header.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'connections_section.dart';
import 'data_file_section.dart';
import 'data_sources_section.dart';
import 'llm_api_keys_section.dart';
import 'portfolios_section.dart';
import 'privacy_data_section.dart';

/// Sidebar destinations for Settings. Only one body is mounted at a time.
enum SettingsNavSection {
  appearance,
  dataSources,
  portfolios,
  apiKeys,
  connections,
  dataFile,
  privacy,
  about,
}

extension SettingsNavSectionX on SettingsNavSection {
  String get title => switch (this) {
        SettingsNavSection.about => 'About',
        SettingsNavSection.appearance => 'Appearance',
        SettingsNavSection.dataSources => 'Data sources',
        SettingsNavSection.portfolios => 'Portfolios',
        SettingsNavSection.apiKeys => 'API keys',
        SettingsNavSection.connections => 'Connections',
        SettingsNavSection.dataFile => 'Data file',
        SettingsNavSection.privacy => 'Privacy & data',
      };

  String get subtitle => switch (this) {
        SettingsNavSection.about => AppCopy.tagline,
        SettingsNavSection.appearance => 'Theme, lists, numbers, charts',
        SettingsNavSection.dataSources =>
          'Market providers, crypto venues, credentials',
        SettingsNavSection.portfolios =>
          'Practice cash and live connections',
        SettingsNavSection.apiKeys => 'LLM providers stored on this device',
        SettingsNavSection.connections =>
          'Agents and exchange credentials',
        SettingsNavSection.dataFile =>
          'Config path, import, and export',
        SettingsNavSection.privacy =>
          'Clear chats, disconnect, wipe local data',
      };

  IconData get icon => switch (this) {
        SettingsNavSection.about => LucideIcons.info,
        SettingsNavSection.appearance => LucideIcons.palette,
        SettingsNavSection.dataSources => LucideIcons.database,
        SettingsNavSection.portfolios => LucideIcons.wallet,
        SettingsNavSection.apiKeys => LucideIcons.keyRound,
        SettingsNavSection.connections => LucideIcons.plug,
        SettingsNavSection.dataFile => LucideIcons.fileJson,
        SettingsNavSection.privacy => LucideIcons.shield,
      };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Wide layout always has a selection; narrow starts on the nav list.
  SettingsNavSection _selected = SettingsNavSection.appearance;

  /// On narrow viewports, null means show the section list only.
  SettingsNavSection? _narrowSelected;

  void _select(SettingsNavSection section, {required bool wide}) {
    setState(() {
      _selected = section;
      if (!wide) {
        _narrowSelected = section;
      }
    });
  }

  void _backToNavList() {
    setState(() => _narrowSelected = null);
  }

  Widget _bodyFor(SettingsNavSection section, {required bool wide}) {
    return switch (section) {
      SettingsNavSection.about => const AboutSectionBody(),
      SettingsNavSection.appearance => const AppearanceSectionBody(),
      SettingsNavSection.dataSources => const DataSourcesSectionBody(),
      SettingsNavSection.portfolios => PortfoliosSectionBody(
          onOpenDataSources: () => _select(
            SettingsNavSection.dataSources,
            wide: wide,
          ),
        ),
      SettingsNavSection.apiKeys => const LlmApiKeysSectionBody(),
      SettingsNavSection.connections => const ConnectionsSectionBody(),
      SettingsNavSection.dataFile => const DataFileSectionBody(),
      SettingsNavSection.privacy => const PrivacyDataSectionBody(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabPageHeader(
          title: 'Settings',
          subtitle:
              'Choose a section, then change only what’s on this device.',
        ),
        Expanded(
          child: MasterDetailShell<SettingsNavSection>(
            selected: _selected,
            narrowSelected: _narrowSelected,
            onNarrowBack: _backToNavList,
            sidebarBuilder: (context, highlighted, {required wide}) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  for (var i = 0;
                      i < SettingsNavSection.values.length;
                      i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    MasterDetailNavTile(
                      title: SettingsNavSection.values[i].title,
                      icon: SettingsNavSection.values[i].icon,
                      selected:
                          highlighted == SettingsNavSection.values[i],
                      onTap: () => _select(
                        SettingsNavSection.values[i],
                        wide: wide,
                      ),
                    ),
                  ],
                ],
              );
            },
            contentBuilder: (context, section, {required showBack, onBack}) {
              final wide = MediaQuery.sizeOf(context).width >=
                  SettingsScreen.wideBreakpoint;
              return MasterDetailContentPane(
                key: ValueKey(section),
                title: section.title,
                subtitle: section.subtitle,
                showBack: showBack,
                onBack: onBack,
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    KeyedSubtree(
                      key: ValueKey(section),
                      child: _bodyFor(section, wide: wide),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
