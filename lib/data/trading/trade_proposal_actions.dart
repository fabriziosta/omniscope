import '../agents/agent_activity.dart';
import '../agents/agent_activity_repository.dart';
import '../agents/agent_app_settings.dart';
import '../agents/trade_proposal.dart';
import '../agents/trade_proposal_repository.dart';
import '../portfolio/portfolio_catalog.dart';
import 'order_models.dart';
import 'trade_executor.dart';

/// Confirm / Dismiss / portfolio resolution for Agents chat approvals.
class TradeProposalActions {
  TradeProposalActions({
    required this._appSettings,
    required this._proposals,
    required this._activity,
    required this._tradeExecutor,
  });

  final AgentAppSettings _appSettings;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final TradeExecutor _tradeExecutor;

  List<TradableVenue> get tradableVenues => _tradeExecutor.tradableVenues;

  /// Preferred portfolio when Autopilot default is set and still valid;
  /// otherwise null if the user must pick on Confirm (multiple targets).
  String? preferredPortfolioId() {
    final preferred = _appSettings.autopilotExchangeId?.trim();
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
  bool get needsPortfolioPicker => preferredPortfolioId() == null;

  /// Resolve a concrete portfolio id for Confirm / Autopilot.
  ///
  /// Order: explicit [targetPortfolioId] → global default / single venue →
  /// null when still ambiguous.
  String? resolveConfirmPortfolioId({String? targetPortfolioId}) {
    final explicit = targetPortfolioId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (_tradeExecutor.venueForId(explicit) != null) return explicit;
      return null;
    }
    return preferredPortfolioId();
  }

  /// Stamp id for a new proposal: preferred when known, else Practice hint.
  String resolveTargetExchangeId() {
    return preferredPortfolioId() ?? PortfolioDescriptor.practiceId;
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

    final portfolioId = resolveConfirmPortfolioId(
      targetPortfolioId: targetPortfolioId,
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
