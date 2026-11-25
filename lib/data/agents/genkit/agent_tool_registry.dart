/// Stable Genkit tool ids registered by [OmniscopeAgentTools.defineAll].
abstract final class AgentToolIds {
  static const getQuotes = 'getQuotes';
  static const getHistory = 'getHistory';
  static const getPracticePortfolio = 'getPracticePortfolio';
  static const getLiveBalances = 'getLiveBalances';
  static const getInvestInterest = 'getInvestInterest';
  static const getMandate = 'getMandate';
  static const getAgentPnl = 'getAgentPnl';
  static const proposeInvestInterestDiff = 'proposeInvestInterestDiff';
  static const getAgentMemory = 'getAgentMemory';
  static const rememberFact = 'rememberFact';
  static const forgetFact = 'forgetFact';
  static const getAgentFleetStatus = 'getAgentFleetStatus';
  static const setChatAutopilot = 'setChatAutopilot';
  static const getChatFocusSymbols = 'getChatFocusSymbols';
  static const pinChatSymbols = 'pinChatSymbols';
  static const unpinChatSymbols = 'unpinChatSymbols';

  static const all = <String>[
    getQuotes,
    getHistory,
    getPracticePortfolio,
    getLiveBalances,
    getInvestInterest,
    getMandate,
    getAgentPnl,
    proposeInvestInterestDiff,
    getAgentMemory,
    rememberFact,
    forgetFact,
    getAgentFleetStatus,
    setChatAutopilot,
    getChatFocusSymbols,
    pinChatSymbols,
    unpinChatSymbols,
  ];

  /// Shared-memory tools (only when the chat has Memory on).
  static const memoryToolIds = <String>[
    getAgentMemory,
    rememberFact,
    forgetFact,
  ];

  /// Per-chat focus symbol tools (always available).
  static const focusSymbolToolIds = <String>[
    getChatFocusSymbols,
    pinChatSymbols,
    unpinChatSymbols,
  ];
}

/// Metadata for one Omniscope agent tool (catalog entry; not the Genkit fn).
class AgentToolDefinition {
  const AgentToolDefinition({
    required this.id,
    required this.shortDescription,
  });

  final String id;

  /// One-line description for prompts and docs.
  final String shortDescription;
}

/// Single source of truth for Omniscope agent tools and role → tool ACL.
///
/// Implementations stay in [OmniscopeAgentTools.defineAll]; this registry owns
/// ids, short descriptions, and which specialties may invoke each tool.
class AgentToolRegistry {
  AgentToolRegistry._();

  /// Default tool ids when [toolsByRole] has no entry for a role id.
  static const List<String> defaultToolIds = [
    AgentToolIds.getQuotes,
    AgentToolIds.getHistory,
    AgentToolIds.getInvestInterest,
    AgentToolIds.getMandate,
    AgentToolIds.getAgentMemory,
    AgentToolIds.rememberFact,
    AgentToolIds.forgetFact,
    AgentToolIds.getAgentFleetStatus,
    AgentToolIds.setChatAutopilot,
    AgentToolIds.getChatFocusSymbols,
    AgentToolIds.pinChatSymbols,
    AgentToolIds.unpinChatSymbols,
  ];

  static const List<AgentToolDefinition> catalog = [
    AgentToolDefinition(
      id: AgentToolIds.getQuotes,
      shortDescription:
          'Latest quotes for equities or crypto spot (price, change, meta)',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getHistory,
      shortDescription:
          'Recent candle / close history for a symbol (whitelisted range)',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getPracticePortfolio,
      shortDescription: 'Practice (paper) cash and holdings snapshot',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getLiveBalances,
      shortDescription: 'Live exchange balances when credentials unlock them',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getInvestInterest,
      shortDescription: 'User Invest interest watch list',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getMandate,
      shortDescription: 'Settings → Mandate goal, universe, and risk rails',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getAgentPnl,
      shortDescription: 'Read-only agent fill P&L by chat or specialty',
    ),
    AgentToolDefinition(
      id: AgentToolIds.proposeInvestInterestDiff,
      shortDescription:
          'Propose Confirm-gated Invest interest add/remove/set changes',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getAgentMemory,
      shortDescription: 'Shared durable facts across Memory-on chats',
    ),
    AgentToolDefinition(
      id: AgentToolIds.rememberFact,
      shortDescription: 'Store a short shared fact for future chats',
    ),
    AgentToolDefinition(
      id: AgentToolIds.forgetFact,
      shortDescription: 'Remove a shared fact by id or matching text',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getAgentFleetStatus,
      shortDescription:
          'Autopilot chats, Schedule, pending Confirm, and daily fill rails',
    ),
    AgentToolDefinition(
      id: AgentToolIds.setChatAutopilot,
      shortDescription:
          'Enable or disable Autopilot for this chat (immediate)',
    ),
    AgentToolDefinition(
      id: AgentToolIds.getChatFocusSymbols,
      shortDescription: 'Symbols pinned for this chat (not Invest interest)',
    ),
    AgentToolDefinition(
      id: AgentToolIds.pinChatSymbols,
      shortDescription: 'Pin symbols to this chat focus list (immediate)',
    ),
    AgentToolDefinition(
      id: AgentToolIds.unpinChatSymbols,
      shortDescription: 'Unpin symbols from this chat focus list (immediate)',
    ),
  ];

  /// Role id → ordered tool ids granted to that specialty.
  static const Map<String, List<String>> toolsByRole = {
    'marketResearch': [
      AgentToolIds.getQuotes,
      AgentToolIds.getHistory,
      AgentToolIds.getInvestInterest,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
      AgentToolIds.proposeInvestInterestDiff,
    ],
    'liveBalanceExplainer': [
      AgentToolIds.getLiveBalances,
      AgentToolIds.getQuotes,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
    ],
    'portfolioGuide': [
      AgentToolIds.getPracticePortfolio,
      AgentToolIds.getLiveBalances,
      AgentToolIds.getQuotes,
      AgentToolIds.getInvestInterest,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentPnl,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
      AgentToolIds.proposeInvestInterestDiff,
    ],
    'intradayTrading': [
      AgentToolIds.getQuotes,
      AgentToolIds.getHistory,
      AgentToolIds.getPracticePortfolio,
      AgentToolIds.getLiveBalances,
      AgentToolIds.getInvestInterest,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentPnl,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
      AgentToolIds.proposeInvestInterestDiff,
    ],
    'cryptoSpotGuide': [
      AgentToolIds.getQuotes,
      AgentToolIds.getHistory,
      AgentToolIds.getInvestInterest,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
    ],
    'marketsLiteracy': [
      AgentToolIds.getQuotes,
      AgentToolIds.getHistory,
      AgentToolIds.getInvestInterest,
      AgentToolIds.getMandate,
      AgentToolIds.getAgentMemory,
      AgentToolIds.rememberFact,
      AgentToolIds.forgetFact,
      AgentToolIds.getAgentFleetStatus,
      AgentToolIds.setChatAutopilot,
      AgentToolIds.getChatFocusSymbols,
      AgentToolIds.pinChatSymbols,
      AgentToolIds.unpinChatSymbols,
    ],
  };

  static final Map<String, AgentToolDefinition> _byId = {
    for (final t in catalog) t.id: t,
  };

  /// Tool ids granted to [roleId] (falls back to [defaultToolIds]).
  ///
  /// When [memoryEnabled] is false, shared-memory tools are omitted.
  static List<String> toolIdsForRole(
    String roleId, {
    bool memoryEnabled = true,
  }) {
    final base = toolsByRole[roleId] ?? defaultToolIds;
    if (memoryEnabled) return List<String>.unmodifiable(base);
    return List<String>.unmodifiable([
      for (final id in base)
        if (!AgentToolIds.memoryToolIds.contains(id)) id,
    ]);
  }

  /// Role ids that include [toolId] in their ACL.
  static List<String> rolesForTool(String toolId) {
    return [
      for (final entry in toolsByRole.entries)
        if (entry.value.contains(toolId)) entry.key,
    ];
  }

  static AgentToolDefinition? definitionFor(String toolId) => _byId[toolId];

  /// Prompt / docs block listing tools for [roleId].
  static String describeToolsForRole(
    String roleId, {
    bool memoryEnabled = true,
  }) {
    final ids = toolIdsForRole(roleId, memoryEnabled: memoryEnabled);
    if (ids.isEmpty) return '';
    final lines = <String>[];
    for (final id in ids) {
      final def = _byId[id];
      if (def == null) {
        lines.add('- $id');
      } else {
        lines.add('- ${def.id}: ${def.shortDescription}');
      }
    }
    return 'Available tools:\n${lines.join('\n')}';
  }
}
