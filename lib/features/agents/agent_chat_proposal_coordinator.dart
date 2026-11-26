import '../../data/agents/invest_interest_proposal_actions.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/trading/trade_proposal_actions.dart';

/// Confirm / dismiss trade and Invest interest proposals for one chat thread.
class AgentChatProposalCoordinator {
  AgentChatProposalCoordinator({
    required TradeProposalActions proposalActions,
    required this.chatId,
    required AgentActivityRepository activity,
    required AgentChatRepository chats,
    InvestInterestProposalRepository? investInterestProposals,
    FavoritesRepository? favorites,
  })  : _proposalActions = proposalActions,
        _investInterestActions = _buildInvestInterestActions(
          investInterestProposals: investInterestProposals,
          activity: activity,
          favorites: favorites,
          chats: chats,
        ); // ignore: prefer_initializing_formals — paired with factory helper

  final String chatId;
  final TradeProposalActions _proposalActions;
  final InvestInterestProposalActions? _investInterestActions;

  static InvestInterestProposalActions? _buildInvestInterestActions({
    InvestInterestProposalRepository? investInterestProposals,
    required AgentActivityRepository activity,
    FavoritesRepository? favorites,
    required AgentChatRepository chats,
  }) {
    final repo = investInterestProposals;
    final fav = favorites;
    if (repo == null || fav == null) return null;
    return InvestInterestProposalActions(
      proposals: repo,
      activity: activity,
      favorites: fav,
      chats: chats,
    );
  }

  Future<String?> confirmProposal(
    String proposalId, {
    bool autopilot = false,
    String? targetPortfolioId,
  }) =>
      _proposalActions.confirm(
        proposalId,
        autopilot: autopilot,
        targetPortfolioId: targetPortfolioId,
      );

  Future<String?> dismissProposal(String proposalId) =>
      _proposalActions.dismiss(proposalId);

  Future<String?> confirmInvestInterestProposal(
    String proposalId, {
    bool autopilot = false,
  }) async {
    final actions = _investInterestActions;
    if (actions == null) {
      return 'Invest interest is not available.';
    }
    return actions.confirm(proposalId, autopilot: autopilot);
  }

  Future<String?> dismissInvestInterestProposal(String proposalId) async {
    final actions = _investInterestActions;
    if (actions == null) {
      return 'Invest interest is not available.';
    }
    return actions.dismiss(proposalId);
  }

  /// When Autopilot turns on for this chat, apply pending add-only Invest
  /// interest proposals (same rules as apply-at-send).
  Future<int> applyPendingAutopilotInvestInterest() async {
    final actions = _investInterestActions;
    if (actions == null) return 0;
    return actions.applyPendingAutopilotAddsForChat(chatId);
  }
}
