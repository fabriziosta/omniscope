import '../agents/agent_activity.dart';
import '../agents/agent_activity_repository.dart';
import '../agents/agent_app_settings.dart';
import '../agents/agent_chat_repository.dart';
import '../agents/agent_pnl_service.dart';
import '../agents/trade_proposal.dart';
import '../agents/trade_proposal_repository.dart';
import '../market/market_data_client.dart';
import '../notifications/app_notification.dart';
import '../notifications/app_notification_repository.dart';
import '../portfolio/portfolio_catalog.dart';
import '../portfolio/portfolio_repository.dart';
import '../settings/mandate_settings.dart';
import 'order_models.dart';
import 'trade_executor.dart';

/// Confirm / Dismiss / portfolio resolution for Agents chat approvals.
class TradeProposalActions {
  TradeProposalActions({
    required this._appSettings,
    required this._proposals,
    required this._activity,
    required this._tradeExecutor,
    this._marketData,
    this._portfolio,
    this._chats,
    this._notifications,
  });

  final AgentAppSettings _appSettings;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final TradeExecutor _tradeExecutor;
  final MarketDataClient? _marketData;
  final PortfolioRepository? _portfolio;
  final AgentChatRepository? _chats;
  final AppNotificationRepository? _notifications;

  /// Mandate for [proposal]'s originating chat (defaults when unknown).
  ChatMandate mandateFor(TradeProposal proposal) {
    final chatId = proposal.chatId?.trim();
    if (chatId != null && chatId.isNotEmpty && _chats != null) {
      return _chats.threadFor(chatId).mandate;
    }
    return ChatMandate.defaults;
  }

  List<TradableVenue> get tradableVenues => _tradeExecutor.tradableVenues;

  /// Preferred portfolio when this chat's Autopilot portfolio is set and valid;
  /// otherwise null if the user must pick on Confirm (multiple targets).
  String? preferredPortfolioId({String? chatId}) {
    final scoped = chatId?.trim();
    if (scoped != null && scoped.isNotEmpty && _chats != null) {
      final preferred =
          _chats.threadFor(scoped).agentSettings.autopilotExchangeId?.trim();
      if (preferred != null && preferred.isNotEmpty) {
        if (_tradeExecutor.venueForId(preferred) != null) return preferred;
      }
    }
    final venues = _tradeExecutor.tradableVenues;
    if (venues.length == 1) return venues.first.id;
    if (_tradeExecutor.liveVenues.isEmpty) {
      return PortfolioDescriptor.practiceId;
    }
    return null;
  }

  /// True when Confirm needs a portfolio picker (no default + multiple targets).
  bool needsPortfolioPicker({String? chatId}) =>
      preferredPortfolioId(chatId: chatId) == null;

  /// Resolve a concrete portfolio id for Confirm / Autopilot.
  ///
  /// Order: explicit [targetPortfolioId] → chat Autopilot portfolio /
  /// single venue → null when still ambiguous.
  String? resolveConfirmPortfolioId({
    String? targetPortfolioId,
    String? chatId,
  }) {
    final explicit = targetPortfolioId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (_tradeExecutor.venueForId(explicit) != null) return explicit;
      return null;
    }
    return preferredPortfolioId(chatId: chatId);
  }

  /// Stamp id for a new proposal: preferred when known, else Practice hint.
  String resolveTargetExchangeId({String? chatId}) {
    return preferredPortfolioId(chatId: chatId) ??
        PortfolioDescriptor.practiceId;
  }

  String portfolioDisplayName(String exchangeId) {
    final venue = _tradeExecutor.venueForId(exchangeId);
    if (venue != null) return venue.displayName;
    if (exchangeId == PortfolioDescriptor.practiceId) return 'Practice';
    return exchangeId;
  }

  /// Effective max notional from chat Mandate ∩ Agents Autopilot settings.
  double? effectiveMaxNotional(TradeProposal proposal) {
    final mandateCap = mandateFor(proposal).maxNotionalPerProposal;
    final appCap = _appSettings.autopilotMaxNotional;
    if (mandateCap == null) return appCap;
    if (appCap == null) return mandateCap;
    return mandateCap < appCap ? mandateCap : appCap;
  }

  /// Pre-flight Autopilot / Confirm rails. Returns an error message or null.
  ///
  /// [blockConfirmOnNotional] applies the notional cap to manual Confirm.
  /// Fill-budget and daily-loss stops only apply when [autopilot] is true.
  /// Daily fill / loss rails are scoped to [proposal.chatId].
  Future<String?> evaluateRiskRails(
    TradeProposal proposal, {
    required bool autopilot,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now().toUtc();
    final mandate = mandateFor(proposal);
    final maxNotional = effectiveMaxNotional(proposal);
    if (maxNotional != null && maxNotional > 0) {
      final price = await _estimatePrice(proposal.symbol);
      if (price != null && price > 0) {
        final notional = proposal.quantity * price;
        if (notional > maxNotional) {
          return 'Notional \$${notional.toStringAsFixed(2)} exceeds max '
              '\$${maxNotional.toStringAsFixed(2)} per proposal.';
        }
      }
    }

    if (!autopilot) return null;

    final chatId = proposal.chatId?.trim();
    final maxFills = mandate.maxAutopilotFillsPerDay;
    final fillsToday = AgentPnlService.autopilotFillCountForUtcDay(
      proposals: _proposals.proposals,
      now: at,
      chatId: chatId,
    );
    if (fillsToday >= maxFills) {
      return 'Autopilot daily fill budget reached ($maxFills).';
    }

    final maxLoss = mandate.maxDailyRealizedLoss;
    if (maxLoss != null && maxLoss > 0) {
      final realizedToday = AgentPnlService.realizedPnlForUtcDay(
        proposals: _proposals.proposals,
        now: at,
        chatId: chatId,
      );
      if (realizedToday <= -maxLoss) {
        return 'Autopilot halted: daily realized loss '
            '\$${(-realizedToday).toStringAsFixed(2)} reached the '
            '\$${maxLoss.toStringAsFixed(2)} stop.';
      }
    }
    return null;
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
      chatId: proposal.chatId,
    );
    if (portfolioId == null) {
      return 'Choose a portfolio before confirming.';
    }

    final railError = await evaluateRiskRails(proposal, autopilot: autopilot);
    if (railError != null) {
      if (autopilot) {
        await _proposals.upsert(
          proposal.copyWith(status: TradeProposalStatus.skipped),
        );
        await _activity.add(
          AgentActivityEvent(
            id: AgentActivityEvent.newId(),
            kind: AgentActivityKind.autopilotSubmitted,
            roleId: proposal.roleId,
            createdAt: DateTime.now().toUtc(),
            exchangeId: portfolioId,
            proposalId: proposal.id,
            symbol: proposal.symbol,
            summary: railError,
          ),
        );
        final isLossStop = railError.contains('daily realized loss');
        if (isLossStop) {
          await _haltChatAutopilot(
            chatId: proposal.chatId,
            roleId: proposal.roleId,
            symbol: proposal.symbol,
            reason: railError,
          );
        }
        return railError;
      }
      // Manual Confirm: hard-block only on notional; loss/fill are Autopilot-only.
      if (railError.contains('Notional')) {
        return railError;
      }
    }

    final avgCostBefore = _avgCostBeforeFill(
      portfolioId: portfolioId,
      symbol: proposal.symbol,
      side: proposal.side,
    );

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
      final fillPrice = result.fillPrice ?? await _estimatePrice(proposal.symbol);
      final fillNotional =
          fillPrice != null ? fillPrice * proposal.quantity : null;
      final filledAt = DateTime.now().toUtc();
      double? realizedPnl;
      if (proposal.side == TradeProposalSide.sell &&
          fillPrice != null &&
          avgCostBefore != null) {
        realizedPnl = (fillPrice - avgCostBefore) * proposal.quantity;
      }
      await _proposals.upsert(
        confirmed.copyWith(
          status: TradeProposalStatus.executed,
          orderId: result.orderId,
          autopilot: autopilot,
          clearExecutionError: true,
          fillPrice: fillPrice,
          fillNotional: fillNotional,
          filledAt: filledAt,
          realizedPnl: realizedPnl,
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
              '${result.rawStatus != null ? ' (${result.rawStatus})' : ''}'
              '${fillPrice != null ? ' @ ${fillPrice.toStringAsFixed(2)}' : ''}'
              '${realizedPnl != null ? ' · realized ${realizedPnl.toStringAsFixed(2)}' : ''}',
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

  Future<double?> _estimatePrice(String symbol) async {
    final market = _marketData;
    if (market == null) return null;
    try {
      final quotes = await market.getQuotes([symbol.trim().toUpperCase()]);
      if (quotes.isEmpty || quotes.first.price <= 0) return null;
      return quotes.first.price;
    } catch (_) {
      return null;
    }
  }

  double? _avgCostBeforeFill({
    required String portfolioId,
    required String symbol,
    required TradeProposalSide side,
  }) {
    if (side != TradeProposalSide.sell) return null;
    if (portfolioId != PortfolioDescriptor.practiceId) return null;
    final holding = _portfolio?.state.holdingFor(symbol.trim().toUpperCase());
    if (holding == null || holding.shares <= 0) return null;
    return holding.avgCost;
  }

  Future<void> _haltChatAutopilot({
    required String? chatId,
    required String roleId,
    required String symbol,
    required String reason,
  }) async {
    final id = chatId?.trim();
    if (id != null && id.isNotEmpty) {
      await _chats?.setAutopilotEnabled(id, enabled: false);
    }
    await _notifications?.enqueue(
      AppNotification(
        id: AppNotification.newId(),
        kind: AppNotificationKind.autopilotRiskHalt,
        roleId: roleId,
        createdAt: DateTime.now().toUtc(),
        title: 'Autopilot halted',
        body: reason,
        symbol: symbol,
        chatId: id,
      ),
    );
  }
}
