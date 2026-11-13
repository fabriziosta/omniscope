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

  var _sending = false;
  var _actingOnProposal = false;

  bool get sending => _sending;
  bool get actingOnProposal => _actingOnProposal;

  bool get hasTradableExchange => _tradeExecutor.canTrade;

  String? resolveTargetExchangeId(AgentConnection connection) {
    final preferred = connection.autopilotExchangeId?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      if (_tradeExecutor.venueForId(preferred) != null) return preferred;
    }
    final venues = _tradeExecutor.tradableVenues;
    if (venues.isEmpty) return null;
    return venues.first.id;
  }

  CryptoExchangeClient? _clientForExchange(String exchangeId) {
    final client = _cryptoRegistry.clientForId(exchangeId);
    if (client == null) return null;
    if (!_dataSources.isCryptoEnabled(exchangeId)) return null;
    return client;
  }

  Future<AgentChatSendResult> sendFreeform(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) {
      return const AgentChatSendOk();
    }
    return sendUserMessage(
      content: trimmed,
      kind: AgentChatMessageKind.freeform,
      symbolHint: MarketContextBuilder.extractSymbolHint(trimmed),
    );
  }

  Future<AgentChatSendResult> sendRun({
    required String symbol,
    String? side,
    double? quantity,
  }) {
    if (AgentRolePrompts.supportsTradeProposals(role.id) &&
        !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }
    final prompt = AgentRolePrompts.runUserPrompt(
      roleId: role.id,
      symbol: symbol,
      side: side,
      quantity: quantity,
    );
    return sendUserMessage(
      content: prompt,
      kind: AgentChatMessageKind.run,
      symbolHint: symbol,
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
            'Configure a connected exchange under Settings → Data sources '
            'before requesting trade suggestions.',
      ),
    );
    return const AgentChatSendBlockedNoExchange();
  }

  Future<AgentChatSendResult> sendUserMessage({
    required String content,
    required AgentChatMessageKind kind,
    String? symbolHint,
  }) async {
    final connection = _agents.forRoleId(role.id);
    if (!connection.connected) {
      return const AgentChatSendFailed('Connect this agent before chatting.');
    }

    final wantsTrade = AgentRolePrompts.supportsTradeProposals(role.id);
    if (wantsTrade && !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }

    final exchangeId = wantsTrade ? resolveTargetExchangeId(connection) : null;

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
        exchangeId: exchangeId,
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
      if (hint != null && hint.isNotEmpty) {
        if (wantsTrade && exchangeId != null) {
          marketContext = await builder.buildForTradingSymbol(
            symbol: hint,
            exchangeClient: _clientForExchange(exchangeId),
          );
        } else {
          marketContext = await builder.buildForSymbol(hint);
        }
      } else if (wantsTrade && exchangeId != null) {
        final client = _clientForExchange(exchangeId);
        if (client != null) {
          marketContext = await builder.buildLiveExchangeContext(
            client: client,
          );
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
      if (wantsTrade && exchangeId != null) {
        final json = TradeProposalParser.extractJsonMap(reply);
        if (json != null) {
          proposal = TradeProposal.fromLlmJson(
            json,
            roleId: role.id,
            exchangeId: exchangeId,
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
              exchangeId: exchangeId,
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
        exchangeId: proposal.exchangeId,
        proposalId: proposal.id,
        symbol: proposal.symbol,
        summary: 'Autopilot submitting ${proposal.side.label} '
            '${proposal.quantity} ${proposal.symbol}',
      ),
    );
    await confirmProposal(proposal.id, autopilot: true);
  }

  Future<String?> confirmProposal(
    String proposalId, {
    bool autopilot = false,
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

    _actingOnProposal = true;
    notifyListeners();
    try {
      await _proposals.upsert(
        proposal.copyWith(
          status: TradeProposalStatus.confirmed,
          autopilot: autopilot,
        ),
      );
      if (!autopilot) {
        await _activity.add(
          AgentActivityEvent(
            id: AgentActivityEvent.newId(),
            kind: AgentActivityKind.proposalConfirmed,
            roleId: role.id,
            createdAt: DateTime.now().toUtc(),
            exchangeId: proposal.exchangeId,
            proposalId: proposal.id,
            symbol: proposal.symbol,
            summary:
                'Confirmed ${proposal.side.label} ${proposal.quantity} ${proposal.symbol}',
          ),
        );
      }

      final result = await _tradeExecutor.submit(
        OrderRequest(
          exchangeId: proposal.exchangeId,
          symbol: proposal.symbol,
          side: orderSide,
          quantity: proposal.quantity,
          clientOrderId: proposal.id,
        ),
      );

      if (result.success) {
        await _proposals.upsert(
          proposal.copyWith(
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
            exchangeId: proposal.exchangeId,
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
        proposal.copyWith(
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
          exchangeId: proposal.exchangeId,
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
