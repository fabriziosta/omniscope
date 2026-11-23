import '../trade_proposal.dart';

/// In-process Genkit agent names + orchestrator delegation helpers (no HTTP).
///
/// Specialists are registered as `omniscope_<roleId>` on one Genkit instance so
/// `agents()` middleware can inject `delegate_to_omniscope_<roleId>` tools.
abstract final class AgentPeerDelegation {
  static const agentNamePrefix = 'omniscope_';
  static const orchestratorName = 'omniscope_orchestrator';

  /// Genkit registry name for a specialty role.
  static String agentName(String roleId) => '$agentNamePrefix$roleId';

  /// Role id from a Genkit agent name, or null if not an Omniscope specialty.
  static String? roleIdFromAgentName(String agentName) {
    if (agentName == orchestratorName) return null;
    if (!agentName.startsWith(agentNamePrefix)) return null;
    final id = agentName.substring(agentNamePrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Default prefix used by Genkit `agents()` middleware.
  static const delegateToolPrefix = 'delegate_to';

  static String delegateToolName(String roleId) =>
      '${delegateToolPrefix}_${agentName(roleId)}';

  /// Registry description for a specialty (manifest description + handoff).
  static String peerDescription({
    required String roleId,
    required String catalogDescription,
  }) {
    final base = catalogDescription.trim();
    final handoff = switch (roleId) {
      'intradayTrading' =>
        ' Use when a discovered symbol needs a trade check / risk sizing. '
            'Pass a self-contained task with the symbol and thesis. '
            'The sub-agent ends with fenced trade JSON when recommending an action.',
      'marketResearch' =>
        ' Use for plain-language research briefs on a symbol or topic.',
      'liveBalanceExplainer' =>
        ' Use to explain live exchange balances and totals.',
      'portfolioGuide' =>
        ' Use for allocation, concentration, diversification, and '
            'practice sizing reviews.',
      'cryptoSpotGuide' =>
        ' Use to teach crypto spot pairs, venue tickers, and quote units '
            '(not trade sizing).',
      'marketsLiteracy' =>
        ' Use to teach indices vs ETFs vs stocks and how Markets subgroups '
            'differ (educational, not a research brief).',
      _ => ' Use for specialized help on this role\'s topic.',
    };
    if (base.isEmpty) return handoff.trim();
    return '$base$handoff';
  }

  /// Role ids the orchestrator delegated to (order of first tool call).
  ///
  /// Parses `delegate_to_omniscope_<roleId>` tool names from Genkit `agents()`
  /// middleware outputs. Dedupes while preserving first-seen order.
  static List<String> extractDelegatedRoleIds(
    Iterable<({String toolName, Object? output})> toolOutputs,
  ) {
    final ids = <String>[];
    final seen = <String>{};
    final prefix = '${delegateToolPrefix}_';
    for (final item in toolOutputs) {
      final name = item.toolName.trim();
      if (!name.startsWith(prefix)) continue;
      final agent = name.substring(prefix.length);
      final roleId = roleIdFromAgentName(agent);
      if (roleId == null || !seen.add(roleId)) continue;
      ids.add(roleId);
    }
    return ids;
  }

  /// Compact label for chat message meta (footer under assistant bubbles).
  static String chatMetaLabel(String roleId) {
    final id = roleId.trim();
    return switch (id) {
      'marketResearch' => 'Market Research',
      'liveBalanceExplainer' => 'Live Balance',
      'portfolioGuide' => 'Portfolio Guide',
      'intradayTrading' => 'Intraday',
      'cryptoSpotGuide' => 'Crypto Spot',
      'marketsLiteracy' => 'Markets Literacy',
      'orchestrator' => 'Orchestrator',
      _ => id.isEmpty ? 'Orchestrator' : id,
    };
  }

  /// Pull trade JSON from `delegate_to_omniscope_intradayTrading` tool outputs.
  static Map<String, dynamic>? extractDelegatedTradeJson(
    Iterable<({String toolName, Object? output})> toolOutputs,
  ) {
    final tradingTool = delegateToolName('intradayTrading');
    for (final item in toolOutputs) {
      if (item.toolName != tradingTool) continue;
      final text = delegationResponseText(item.output);
      if (text == null || text.trim().isEmpty) continue;
      final json = TradeProposalParser.extractJsonMap(text);
      if (json != null) return json;
    }
    return null;
  }

  /// Normalize a delegation tool output into the sub-agent response text.
  static String? delegationResponseText(Object? output) {
    if (output == null) return null;
    if (output is String) return output;
    if (output is Map) {
      final response = output['response'];
      if (response is String) return response;
      final nested = output['output'];
      if (nested is Map && nested['response'] is String) {
        return nested['response'] as String;
      }
      if (nested is String) return nested;
    }
    try {
      final dynamic dyn = output;
      final response = dyn.response;
      if (response is String) return response;
    } catch (_) {}
    try {
      final dynamic dyn = output;
      final json = dyn.toJson();
      if (json is Map) return delegationResponseText(json);
    } catch (_) {}
    return output.toString();
  }
}
