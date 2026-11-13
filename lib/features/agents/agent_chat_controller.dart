import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/llm_chat_client.dart';
import '../../data/agents/market_context_builder.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/trading/order_models.dart';
import '../../data/trading/trade_executor.dart';

/// UI feedback from a chat send attempt.
sealed class AgentChatSendResult {
  const AgentChatSendResult();
}

class AgentChatSendOk extends AgentChatSendResult {
  const AgentChatSendOk({this.proposal});

  final TradeProposal? proposal;
}

class AgentChatSendFailed extends AgentChatSendResult {
  const AgentChatSendFailed(this.message);

  final String message;
}

class AgentChatSendBlockedNoExchange extends AgentChatSendResult {
  const AgentChatSendBlockedNoExchange();
}

/// Screen-scoped chat send / clear / confirm orchestration for one agent role.
class AgentChatController extends ChangeNotifier {
  AgentChatController({
    required this.role,
    required this._agents,
    required this._chats,
    required this._marketData,
    required this._llm,
    required this._tradeExecutor,
    required this._proposals,
    required this._activity,
    required this._cryptoRegistry,
    required this._dataSources,
    required this._portfolio,
  });

  final AgentRoleDefinition role;
  final AgentsRepository _agents;
  final AgentChatRepository _chats;
  final MarketDataClient _marketData;
  final LlmChatClient _llm;
  final TradeExecutor _tradeExecutor;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final CryptoExchangeRegistry _cryptoRegistry;
  final DataSourceSettings _dataSources;
  final PortfolioRepository _portfolio;

  var _sending = false;
  var _actingOnProposal = false;

  bool get sending => _sending;
  bool get actingOnProposal => _actingOnProposal;

  bool get hasTradableExchange => _tradeExecutor.canTrade;

  List<TradableVenue> get tradableVenues => _tradeExecutor.tradableVenues;

  /// Connect default when set and still valid; otherwise null if the user
  /// must pick on Confirm (multiple targets, no default).
  String? preferredPortfolioId([AgentConnection? connection]) {
    final conn = connection ?? _agents.forRoleId(role.id);
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
  bool get needsPortfolioPicker => preferredPortfolioId() == null;

  /// Resolve a concrete portfolio id for Confirm / Autopilot.
  ///
  /// Order: explicit [targetPortfolioId] → Connect default / single venue →
  /// error when still ambiguous.
  String? resolveConfirmPortfolioId({
    String? targetPortfolioId,
    AgentConnection? connection,
  }) {
    final explicit = targetPortfolioId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      if (_tradeExecutor.venueForId(explicit) != null) return explicit;
      return null;
    }
    return preferredPortfolioId(connection);
  }

  /// Stamp id for a new proposal: preferred when known, else Practice hint.
  String resolveTargetExchangeId(AgentConnection connection) {
    return preferredPortfolioId(connection) ?? PortfolioDescriptor.practiceId;
  }

  CryptoExchangeClient? _clientForExchange(String exchangeId) {
    if (exchangeId == PortfolioDescriptor.practiceId) return null;
    final client = _cryptoRegistry.clientForId(exchangeId);
    if (client == null) return null;
    if (!_dataSources.isCryptoEnabled(exchangeId)) return null;
    return client;
  }

  /// Prefer [preferredId], else first enabled venue that can fetch balances.
  String? resolveLiveBalanceExchangeId([String? preferredId]) {
    final preferred = preferredId?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      final client = _clientForExchange(preferred);
      if (client != null && client.canFetchPortfolio) return preferred;
    }
    final ready = _cryptoRegistry.portfolioClientsWhere(
      _dataSources.isCryptoEnabled,
    );
    if (ready.isEmpty) return null;
    return ready.first.exchange.id;
  }

  Future<AgentChatSendResult> sendFreeform(
    String text, {
    String? exchangeId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) {
      return const AgentChatSendOk();
    }
    return sendUserMessage(
      content: trimmed,
      kind: AgentChatMessageKind.freeform,
      symbolHint: MarketContextBuilder.extractSymbolHint(trimmed),
      exchangeId: exchangeId,
    );
  }

  Future<AgentChatSendResult> sendRun({
    String symbol = '',
    String? exchangeId,
    String? side,
    double? quantity,
  }) {
    if (AgentRolePrompts.supportsTradeProposals(role.id) &&
        !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }
    final sym = symbol.trim();
    if (sym.isEmpty && !AgentRolePrompts.allowsRunWithoutSymbol(role.id)) {
      return Future.value(
        const AgentChatSendFailed('Enter a symbol to Run.'),
      );
    }
    if (role.id == 'liveBalanceExplainer' &&
        resolveLiveBalanceExchangeId(exchangeId) == null) {
      return Future.value(
        const AgentChatSendFailed(
          'Connect a live exchange under Settings → Data sources to explain '
          'balances.',
        ),
      );
    }
    final prompt = AgentRolePrompts.runUserPrompt(
      roleId: role.id,
      symbol: sym,
      side: side,
      quantity: quantity,
    );
    return sendUserMessage(
      content: prompt,
      kind: AgentChatMessageKind.run,
      symbolHint: sym.isEmpty ? null : sym,
      exchangeId: exchangeId,
    );
  }

  Future<AgentChatSendResult> _blockNoExchange() async {
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.runBlockedNoExchange,
        roleId: role.id,
        createdAt: DateTime.now().toUtc(),
        summary:
            'No trade target available. Practice should always be listed; '
            'try reopening the app.',
      ),
    );
    return const AgentChatSendBlockedNoExchange();
  }

  Future<AgentChatSendResult> sendUserMessage({
    required String content,
    required AgentChatMessageKind kind,
    String? symbolHint,
    String? exchangeId,
  }) async {
    final connection = _agents.forRoleId(role.id);
    if (!connection.connected) {
      return const AgentChatSendFailed('Connect this agent before chatting.');
    }

    final wantsTrade = AgentRolePrompts.supportsTradeProposals(role.id);
    final wantsLiveExplain = AgentRolePrompts.usesLiveBalanceContext(role.id);
    final wantsPractice =
        AgentRolePrompts.usesPracticePortfolioContext(role.id);
    if (wantsTrade && !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }

    final preferredId = wantsTrade ? preferredPortfolioId(connection) : null;
    final stampedId = wantsTrade ? resolveTargetExchangeId(connection) : null;
    final liveExplainId =
        wantsLiveExplain ? resolveLiveBalanceExchangeId(exchangeId) : null;

    final userMessage = AgentChatMessage(
      id: AgentChatMessage.newId(),
      role: AgentChatRole.user,
      content: content,
      createdAt: DateTime.now().toUtc(),
      kind: kind,
    );
    await _chats.append(roleId: role.id, message: userMessage);
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.messageSent,
        roleId: role.id,
        createdAt: DateTime.now().toUtc(),
        exchangeId: stampedId ??
            liveExplainId ??
            (wantsPractice ? PortfolioDescriptor.practiceId : null),
        messageId: userMessage.id,
        symbol: symbolHint?.trim().toUpperCase(),
        summary: content.length > 120 ? '${content.substring(0, 117)}…' : content,
      ),
    );

    _sending = true;
    notifyListeners();

    try {
      String? marketContext;
      final hint = symbolHint?.trim();
      final builder = MarketContextBuilder(_marketData);
      if (wantsPractice || (wantsLiveExplain && role.id != 'liveBalanceExplainer')) {
        final parts = <String>[];
        if (wantsPractice) {
          Map<String, double>? lastPrices;
          if (AgentRolePrompts.usesAllocationContext(role.id) &&
              _portfolio.state.holdings.isNotEmpty) {
            try {
              final quotes = await _marketData.getQuotes([
                for (final h in _portfolio.state.holdings) h.symbol,
              ]);
              lastPrices = {
                for (final q in quotes) q.symbol: q.price,
              };
            } catch (_) {
              // Weights are optional enrichment.
            }
          }
          final practiceCtx = builder.buildPracticePortfolioContext(
            state: _portfolio.state,
            symbolHint: hint,
            listAllHoldings: true,
            lastPrices: lastPrices,
          );
          if (practiceCtx != null) parts.add(practiceCtx);
        }
        if (wantsLiveExplain && liveExplainId != null) {
          final client = _clientForExchange(liveExplainId);
          if (client != null) {
            final liveCtx = await builder.buildLiveExchangeContext(
              client: client,
              symbolHint: hint,
              listAllBalances: true,
            );
            if (liveCtx != null) parts.add(liveCtx);
          }
        }
        if (parts.isNotEmpty) marketContext = parts.join('\n\n');
      } else if (wantsLiveExplain && liveExplainId != null) {
        final client = _clientForExchange(liveExplainId);
        if (client != null) {
          marketContext = await builder.buildLiveExchangeContext(
            client: client,
            symbolHint: hint,
            listAllBalances: true,
          );
        }
      } else if (hint != null && hint.isNotEmpty) {
        if (wantsTrade && stampedId != null) {
          final usePractice = stampedId == PortfolioDescriptor.practiceId ||
              preferredId == null;
          marketContext = await builder.buildForTradingSymbol(
            symbol: hint,
            exchangeClient:
                usePractice ? null : _clientForExchange(stampedId),
            practiceState: usePractice ? _portfolio.state : null,
          );
        } else {
          marketContext = await builder.buildForSymbol(hint);
        }
      } else if (wantsTrade && stampedId != null) {
        if (stampedId == PortfolioDescriptor.practiceId || preferredId == null) {
          marketContext = builder.buildPracticePortfolioContext(
            state: _portfolio.state,
          );
        } else {
          final client = _clientForExchange(stampedId);
          if (client != null) {
            marketContext = await builder.buildLiveExchangeContext(
              client: client,
            );
          }
        }
      }

      final thread = _chats.threadFor(role.id);
      final reply = await _llm.complete(
        connection: connection,
        roleId: role.id,
        messages: thread.messages,
        marketContext: marketContext,
      );

      final assistantId = AgentChatMessage.newId();
      TradeProposal? proposal;
      if (wantsTrade && stampedId != null) {
        final json = TradeProposalParser.extractJsonMap(reply);
        if (json != null) {
          proposal = TradeProposal.fromLlmJson(
            json,
            roleId: role.id,
            exchangeId: stampedId,
            sourceMessageId: assistantId,
            fallbackSymbol: hint,
          );
          await _proposals.upsert(proposal);
          await _activity.add(
            AgentActivityEvent(
              id: AgentActivityEvent.newId(),
              kind: AgentActivityKind.proposalParsed,
              roleId: role.id,
              createdAt: DateTime.now().toUtc(),
              exchangeId: stampedId,
              proposalId: proposal.id,
              messageId: assistantId,
              symbol: proposal.symbol,
              summary:
                  '${proposal.side.label} ${proposal.quantity} ${proposal.symbol}'
                  ' · risk ${proposal.riskApproved ? 'ok' : 'veto'}',
            ),
          );
        }
      }

      await _chats.append(
        roleId: role.id,
        message: AgentChatMessage(
          id: assistantId,
          role: AgentChatRole.assistant,
          content: reply,
          createdAt: DateTime.now().toUtc(),
          proposalId: proposal?.id,
        ),
      );

      if (proposal != null &&
          connection.autopilotEnabled &&
          proposal.isActionable) {
        await _maybeAutopilot(connection, proposal);
        proposal = _proposals.byId(proposal.id) ?? proposal;
      }

      return AgentChatSendOk(proposal: proposal);
    } on LlmChatException catch (e) {
      return AgentChatSendFailed(e.message);
    } catch (e, st) {
      debugPrint('Agent chat send failed: $e\n$st');
      return const AgentChatSendFailed(
        'Could not reach the model. Try again.',
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> _maybeAutopilot(
    AgentConnection connection,
    TradeProposal proposal,
  ) async {
    final targetId = preferredPortfolioId(connection);
    if (targetId == null) {
      // Autopilot needs a Connect default (or a single available target).
      return;
    }
    final pending = _proposals.pendingForRole(role.id);
    if (pending.length > connection.autopilotMaxOpenProposals) {
      await _proposals.upsert(
        proposal.copyWith(status: TradeProposalStatus.skipped),
      );
      return;
    }
    if (connection.autopilotMaxNotional != null) {
      // Without a hard price in the proposal, skip notional gate (Confirm path
      // still available). Autopilot only when risk_approved and caps on count.
    }
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.autopilotSubmitted,
        roleId: role.id,
        createdAt: DateTime.now().toUtc(),
        exchangeId: targetId,
        proposalId: proposal.id,
        symbol: proposal.symbol,
        summary: 'Autopilot submitting ${proposal.side.label} '
            '${proposal.quantity} ${proposal.symbol}',
      ),
    );
    await confirmProposal(
      proposal.id,
      autopilot: true,
      targetPortfolioId: targetId,
    );
  }

  Future<String?> confirmProposal(
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

    final connection = _agents.forRoleId(role.id);
    final portfolioId = resolveConfirmPortfolioId(
      targetPortfolioId: targetPortfolioId,
      connection: connection,
    );
    if (portfolioId == null) {
      return 'Choose a portfolio before confirming.';
    }

    _actingOnProposal = true;
    notifyListeners();
    try {
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
            roleId: role.id,
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
            roleId: role.id,
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
          roleId: role.id,
          createdAt: DateTime.now().toUtc(),
          exchangeId: portfolioId,
          proposalId: proposal.id,
          symbol: proposal.symbol,
          summary: err,
        ),
      );
      return err;
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<String?> dismissProposal(String proposalId) async {
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
        roleId: role.id,
        createdAt: DateTime.now().toUtc(),
        exchangeId: proposal.exchangeId,
        proposalId: proposal.id,
        symbol: proposal.symbol,
        summary: 'Dismissed ${proposal.symbol}',
      ),
    );
    return null;
  }

  Future<void> clearThread() => _chats.clearThread(role.id);
}
