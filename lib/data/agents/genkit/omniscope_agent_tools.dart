import 'package:genkit/genkit.dart';

import '../../market/market_data_client.dart';
import '../../portfolio/models.dart';
import '../../settings/mandate_settings.dart';
import '../../venues/live_venue_capabilities.dart';
import '../agent_memory.dart';
import '../models.dart';
import '../trade_proposal.dart';
import 'agent_tool_registry.dart';
import 'omniscope_fleet_tools.dart';
import 'omniscope_market_tools.dart';
import 'omniscope_memory_tools.dart';
import 'omniscope_portfolio_tools.dart';
import 'omniscope_proposal_tools.dart';

/// Callback that creates a pending Confirm-gated Invest interest proposal.
typedef ProposeInvestInterestFn = Future<String> Function({
  required List<String> add,
  required List<String> remove,
  List<String>? setSymbols,
  required String rationale,
});

/// Store a short shared memory fact (applies immediately).
typedef RememberFactFn = Future<AgentMemoryFact?> Function(String text);

/// Remove a shared memory fact by id or matching text.
typedef ForgetFactFn = Future<bool> Function(String idOrText);

/// Compact fleet / Autopilot / Schedule status (no sibling transcripts).
typedef GetAgentFleetStatusFn = String Function();

/// Enable or disable Autopilot for this chat (applies immediately).
/// Returns a short status message for the model (success or block reason).
typedef SetChatAutopilotFn = Future<String> Function({required bool enabled});

/// Pin symbols onto this chat's focus list (applies immediately).
typedef PinChatSymbolsFn = Future<List<String>> Function(List<String> symbols);

/// Unpin symbols from this chat's focus list (applies immediately).
typedef UnpinChatSymbolsFn = Future<List<String>> Function(
  List<String> symbols,
);

/// Dependencies closed over by Genkit tools for one chat turn.
class OmniscopeAgentToolDeps {
  const OmniscopeAgentToolDeps({
    required this.marketData,
    this.practice,
    this.liveVenue,
    this.symbolHint,
    this.investInterestSymbols = const [],
    this.focusSymbols = const [],
    this.mandate,
    this.answerMood = AgentAnswerMood.plain,
    this.answerMoodNote,
    this.autopilotEnabled = false,
    this.memoryEnabled = true,
    this.memorySummary,
    this.rememberFact,
    this.forgetFact,
    this.getFleetStatus,
    this.setChatAutopilot,
    this.pinChatSymbols,
    this.unpinChatSymbols,
    this.proposeInvestInterest,
    this.tradeProposals = const [],
    this.chatId,
  });

  final MarketDataClient marketData;
  final PortfolioState? practice;
  final LiveVenueCapabilities? liveVenue;
  final String? symbolHint;

  /// User's Markets → Invest interest symbols for this turn.
  final List<String> investInterestSymbols;

  /// This chat's focus symbols (investigated / traded in-thread).
  final List<String> focusSymbols;

  /// This chat's investment policy (goal, universe, risk rails).
  final ChatMandate? mandate;

  /// Per-chat answer mood (delivery style).
  final AgentAnswerMood answerMood;

  /// Optional short style note from per-chat Agent settings.
  final String? answerMoodNote;

  /// Per-chat Autopilot (add-only Invest interest + trades).
  final bool autopilotEnabled;

  /// Per-chat Memory (shared facts read/write).
  final bool memoryEnabled;

  /// Compact shared-memory summary for system prompts (when Memory on).
  final String? memorySummary;

  /// When set with [memoryEnabled], [rememberFact] tool persists a fact.
  final RememberFactFn? rememberFact;

  /// When set with [memoryEnabled], [forgetFact] tool removes a fact.
  final ForgetFactFn? forgetFact;

  /// When set, [getAgentFleetStatus] returns Autopilot / Schedule / rails.
  final GetAgentFleetStatusFn? getFleetStatus;

  /// When set, [setChatAutopilot] enables/disables Autopilot for this chat.
  final SetChatAutopilotFn? setChatAutopilot;

  /// When set, [pinChatSymbols] tool appends to this chat's focus list.
  final PinChatSymbolsFn? pinChatSymbols;

  /// When set, [unpinChatSymbols] tool removes from this chat's focus list.
  final UnpinChatSymbolsFn? unpinChatSymbols;

  /// When set, [proposeInvestInterestDiff] creates a pending proposal.
  final ProposeInvestInterestFn? proposeInvestInterest;

  /// Executed/pending trade proposals for read-only P&L tools.
  final List<TradeProposal> tradeProposals;

  /// Current chat id (for chat-scoped P&L).
  final String? chatId;
}

/// Registers market / portfolio tools on [ai] for the given [deps].
class OmniscopeAgentTools {
  OmniscopeAgentTools._();

  static List<Tool<dynamic, dynamic>> defineAll(
    Genkit ai,
    OmniscopeAgentToolDeps deps,
  ) {
    return [
      ...defineOmniscopeMarketTools(ai, deps),
      ...defineOmniscopePortfolioTools(ai, deps),
      ...defineOmniscopeProposalTools(ai, deps),
      ...defineOmniscopeFleetTools(ai, deps),
      ...defineOmniscopeMemoryTools(ai, deps),
    ];
  }

  static List<Tool<dynamic, dynamic>> forRole({
    required Genkit ai,
    required String roleId,
    required OmniscopeAgentToolDeps deps,
  }) {
    final all = defineAll(ai, deps);
    final byName = {for (final t in all) t.name: t};
    final names = AgentToolRegistry.toolIdsForRole(
      roleId,
      memoryEnabled: deps.memoryEnabled,
    );
    return [for (final n in names) if (byName[n] != null) byName[n]!];
  }
}
