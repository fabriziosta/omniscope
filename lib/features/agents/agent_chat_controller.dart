import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/genkit/genkit_agent_runner.dart';
import '../../data/agents/genkit/genkit_runtime_factory.dart';
import '../../data/agents/genkit/omniscope_agent_tools.dart';
import '../../data/agents/market_context_builder.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../data/venues/live_venue_capabilities.dart';

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
    required this._agentRunner,
    required this._tradeExecutor,
    required this._proposals,
    required this._activity,
    required this._cryptoRegistry,
    required this._dataSources,
    required this._portfolio,
    this._brokerRegistry = BrokerExchangeRegistry.empty,
  });

  final AgentRoleDefinition role;
  final AgentsRepository _agents;
  final AgentChatRepository _chats;
  final MarketDataClient _marketData;
  final GenkitAgentRunner _agentRunner;
  final TradeExecutor _tradeExecutor;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final CryptoExchangeRegistry _cryptoRegistry;
  final BrokerExchangeRegistry _brokerRegistry;
  final DataSourceSettings _dataSources;
  final PortfolioRepository _portfolio;

  late final TradeProposalActions _proposalActions = TradeProposalActions(
    agents: _agents,
    proposals: _proposals,
    activity: _activity,
    tradeExecutor: _tradeExecutor,
  );

  var _sending = false;
  var _actingOnProposal = false;

  bool get sending => _sending;
  bool get actingOnProposal => _actingOnProposal;

  bool get hasTradableExchange => _tradeExecutor.canTrade;

  List<TradableVenue> get tradableVenues => _proposalActions.tradableVenues;

  /// Connect default when set and still valid; otherwise null if the user
  /// must pick on Confirm (multiple targets, no default).
  String? preferredPortfolioId([AgentConnection? connection]) =>
      _proposalActions.preferredPortfolioId(connection, role.id);

  /// True when Confirm needs a portfolio picker (no default + multiple targets).
  bool get needsPortfolioPicker =>
      _proposalActions.needsPortfolioPicker(role.id);

  /// Resolve a concrete portfolio id for Confirm / Autopilot.
  ///
  /// Order: explicit [targetPortfolioId] → Connect default / single venue →
  /// error when still ambiguous.
  String? resolveConfirmPortfolioId({
    String? targetPortfolioId,
    AgentConnection? connection,
  }) =>
      _proposalActions.resolveConfirmPortfolioId(
        roleId: role.id,
        targetPortfolioId: targetPortfolioId,
        connection: connection,
      );

  /// Stamp id for a new proposal: preferred when known, else Practice hint.
  String resolveTargetExchangeId(AgentConnection connection) =>
      _proposalActions.resolveTargetExchangeId(role.id, connection);

  LiveVenueCapabilities? _clientForExchange(String exchangeId) {
    if (exchangeId == PortfolioDescriptor.practiceId) return null;
    final crypto = _cryptoRegistry.clientForId(exchangeId);
    if (crypto != null) {
      if (!_dataSources.isCryptoEnabled(exchangeId)) return null;
      return crypto;
    }
    final broker = _brokerRegistry.clientForId(exchangeId);
    if (broker != null) {
      if (!_dataSources.isBrokerEnabled(exchangeId)) return null;
      return broker;
    }
    return null;
  }

  /// Prefer [preferredId], else first enabled venue that can fetch balances.
  String? resolveLiveBalanceExchangeId([String? preferredId]) {
    final preferred = preferredId?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      final client = _clientForExchange(preferred);
      if (client != null && client.canFetchPortfolio) return preferred;
    }
    final cryptoReady = _cryptoRegistry.portfolioClientsWhere(
      _dataSources.isCryptoEnabled,
    );
    if (cryptoReady.isNotEmpty) return cryptoReady.first.exchange.id;
    final brokerReady = _brokerRegistry.portfolioClientsWhere(
      _dataSources.isBrokerEnabled,
    );
    if (brokerReady.isEmpty) return null;
    return brokerReady.first.broker.id;
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
      final hint = symbolHint?.trim();
      LiveVenueCapabilities? liveVenue;
      if (liveExplainId != null) {
        liveVenue = _clientForExchange(liveExplainId);
      } else if (wantsTrade &&
          stampedId != null &&
          stampedId != PortfolioDescriptor.practiceId) {
        liveVenue = _clientForExchange(stampedId);
      }

      final toolDeps = OmniscopeAgentToolDeps(
        marketData: _marketData,
        practice: (wantsPractice || wantsTrade) ? _portfolio.state : null,
        liveVenue: liveVenue,
        symbolHint: hint,
      );

      final thread = _chats.threadFor(role.id);
      final reply = await _agentRunner.complete(
        connection: connection,
        roleId: role.id,
        messages: thread.messages,
        toolDeps: toolDeps,
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
    } on GenkitAgentException catch (e) {
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
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalActions.confirm(
        proposalId,
        autopilot: autopilot,
        targetPortfolioId: targetPortfolioId,
      );
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<String?> dismissProposal(String proposalId) async {
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalActions.dismiss(proposalId);
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<void> clearThread() => _chats.clearThread(role.id);
}
