import '../agents/agent_activity.dart';
import '../agents/agent_activity_repository.dart';
import '../agents/agents_repository.dart';
import '../agents/models.dart';
import '../agents/trade_proposal.dart';
import '../agents/trade_proposal_repository.dart';
import '../portfolio/portfolio_catalog.dart';
import 'order_models.dart';
import 'trade_executor.dart';

/// Confirm / Dismiss / portfolio resolution shared by chat and Activity.
class TradeProposalActions {
  TradeProposalActions({
    required this._agents,
    required this._proposals,
    required this._activity,
    required this._tradeExecutor,
  });

  final AgentsRepository _agents;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final TradeExecutor _tradeExecutor;

  List<TradableVenue> get tradableVenues => _tradeExecutor.tradableVenues;

  /// Connect default when set and still valid; otherwise null if the user
  /// must pick on Confirm (multiple targets, no default).
  String? preferredPortfolioId([AgentConnection? connection, String? roleId]) {
    final conn = connection ??
        (roleId != null ? _agents.forRoleId(roleId) : null);
    if (conn == null) return null;
    final preferred = conn.autopilotExchangeId?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      if (_tradeExecutor.venueForId(preferred) != null) return preferred;
    }
    final venues = _tradeExecutor.tradableVenues;
    if (venues.length == 1) return venues.first.id;
    if (_tradeExecutor.liveVenues.isEmpty) {
      return PortfolioDescriptor.practiceId;
    }
    return null;
  }

  /// True when Confirm needs a portfolio picker (no default + multiple targets).
  bool needsPortfolioPicker(String roleId) =>
      preferredPortfolioId(_agents.forRoleId(roleId), roleId) == null;

  /// Resolve a concrete portfolio id for Confirm / Autopilot.
  ///
  /// Order: explicit [targetPortfolioId] → Connect default / single venue →
  /// null when still ambiguous.
  String? resolveConfirmPortfolioId({
    required String roleId,
    String? targetPortfolioId,
    AgentConnection? connection,
  }) {
    final explicit = targetPortfolioId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (_tradeExecutor.venueForId(explicit) != null) return explicit;
      return null;
    }
    return preferredPortfolioId(
      connection ?? _agents.forRoleId(roleId),
      roleId,
    );
  }

  /// Stamp id for a new proposal: preferred when known, else Practice hint.
  String resolveTargetExchangeId(String roleId, [AgentConnection? connection]) {
    return preferredPortfolioId(
          connection ?? _agents.forRoleId(roleId),
          roleId,
        ) ??
        PortfolioDescriptor.practiceId;
  }

  String portfolioDisplayName(String exchangeId) {
    final venue = _tradeExecutor.venueForId(exchangeId);
    if (venue != null) return venue.displayName;
    if (exchangeId == PortfolioDescriptor.practiceId) return 'Practice';
    return exchangeId;
  }

  Future<String?> confirm(
    String proposalId, {
    bool autopilot = false,
    String? targetPortfolioId,
  }) async {
    final proposal = _proposals.byId(proposalId);
    if (proposal == null) return 'Proposal not found.';
    if (proposal.status != TradeProposalStatus.pending) {
      return 'This proposal is no longer pending.';
    }
    final orderSide = proposal.side.orderSide;
    if (orderSide == null) {
      return 'Hold proposals cannot be submitted.';
    }
    if (autopilot && !proposal.riskApproved) {
      return 'Autopilot skipped: not risk-approved.';
    }
    if (proposal.quantity <= 0) {
      return 'Quantity must be greater than zero.';
    }

    final connection = _agents.forRoleId(proposal.roleId);
    final portfolioId = resolveConfirmPortfolioId(
      roleId: proposal.roleId,
      targetPortfolioId: targetPortfolioId,
      connection: connection,
    );
    if (portfolioId == null) {
      return 'Choose a portfolio before confirming.';
    }

    final confirmed = proposal.copyWith(
      exchangeId: portfolioId,
      status: TradeProposalStatus.confirmed,
      autopilot: autopilot,
    );
    await _proposals.upsert(confirmed);
    if (!autopilot) {
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: AgentActivityKind.proposalConfirmed,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          exchangeId: portfolioId,
          proposalId: proposal.id,
          symbol: proposal.symbol,
          summary:
              'Confirmed ${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
        ),
      );
    }

    final result = await _tradeExecutor.submit(
      OrderRequest(
        exchangeId: portfolioId,
        symbol: proposal.symbol,
        side: orderSide,
        quantity: proposal.quantity,
        clientOrderId: proposal.id,
      ),
    );

    if (result.success) {
      await _proposals.upsert(
        confirmed.copyWith(
          status: TradeProposalStatus.executed,
          orderId: result.orderId,
          autopilot: autopilot,
          clearExecutionError: true,
        ),
      );
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: AgentActivityKind.orderAck,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          exchangeId: portfolioId,
          proposalId: proposal.id,
          symbol: proposal.symbol,
          summary: 'Order ${result.orderId}'
              '${result.rawStatus != null ? ' (${result.rawStatus})' : ''}',
        ),
      );
      return null;
    }

    final err = result.error ?? 'Order failed.';
    await _proposals.upsert(
      confirmed.copyWith(
        status: TradeProposalStatus.failed,
        executionError: err,
        autopilot: autopilot,
      ),
    );
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.orderFailed,
        roleId: proposal.roleId,
        createdAt: DateTime.now().toUtc(),
        exchangeId: portfolioId,
        proposalId: proposal.id,
        symbol: proposal.symbol,
        summary: err,
      ),
    );
    return err;
  }

  Future<String?> dismiss(String proposalId) async {
    final proposal = _proposals.byId(proposalId);
    if (proposal == null) return 'Proposal not found.';
    if (proposal.status != TradeProposalStatus.pending) {
      return 'This proposal is no longer pending.';
    }
    await _proposals.upsert(
      proposal.copyWith(status: TradeProposalStatus.dismissed),
    );
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.proposalDismissed,
        roleId: proposal.roleId,
        createdAt: DateTime.now().toUtc(),
        exchangeId: proposal.exchangeId,
        proposalId: proposal.id,
        symbol: proposal.symbol,
        summary: 'Dismissed ${proposal.symbol}',
      ),
    );
    return null;
  }
}
