/// Slice names inside [UserConfigStore] document and legacy prefs keys.
abstract final class UserConfigKeys {
  static const version = 'version';
  static const theme = 'theme';
  static const display = 'display';
  static const dataSources = 'dataSources';
  static const secrets = 'secrets';
  static const agents = 'agents';
  static const agentChats = 'agentChats';
  static const paperPortfolio = 'paperPortfolio';
  static const favorites = 'favorites';

  /// Tiny prefs bootstrap: optional absolute path override (desktop).
  static const pathOverridePrefsKey = 'omniscope.config_path.v1';

  /// Prefs blob used when the platform has no config file (Web).
  static const webBlobPrefsKey = 'omniscope.config.v1';

  static const legacyTheme = 'omniscope.theme.v1';
  static const legacyDisplay = 'omniscope.display.v1';
  static const legacyDataSources = 'omniscope.data_sources.v1';
  static const legacySecrets = 'omniscope.env_secrets.v1';
  static const legacyAgents = 'omniscope.agents.v1';
  static const legacyAgentChats = 'omniscope.agent_chats.v1';
  static const legacyPaperPortfolio = 'omniscope.paper_portfolio.v1';

  static const currentVersion = 1;

  static const legacyPrefsKeys = <String>[
    legacyTheme,
    legacyDisplay,
    legacyDataSources,
    legacySecrets,
    legacyAgents,
    legacyAgentChats,
    legacyPaperPortfolio,
  ];
}
