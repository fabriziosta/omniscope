import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_models.dart';
import '../../data/agents/genkit/agent_peer_delegation.dart';
import '../../data/agents/genkit/genkit_agent_runner.dart';
import '../../data/agents/genkit/genkit_runtime_factory.dart';
import '../../data/agents/genkit/omniscope_agent_tools.dart';
import '../../data/agents/invest_interest_proposal.dart';
import '../../data/agents/invest_interest_proposal_actions.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/market_context_builder.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/mandate_settings.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../data/venues/live_venue_capabilities.dart';

/// UI feedback from a chat send attempt.
sealed class AgentChatSendResult {
  const AgentChatSendResult();
}

class AgentChatSendOk extends AgentChatSendResult {
  const AgentChatSendOk({this.proposal, this.investInterestProposal});

  final TradeProposal? proposal;
  final InvestInterestProposal? investInterestProposal;
}

class AgentChatSendFailed extends AgentChatSendResult {
  const AgentChatSendFailed(this.message);

  final String message;
}

class AgentChatSendBlockedNoExchange extends AgentChatSendResult {
  const AgentChatSendBlockedNoExchange();
}

class AgentChatSendBlockedNoLlm extends AgentChatSendResult {
  const AgentChatSendBlockedNoLlm();
}

/// Screen-scoped chat send / clear / confirm for one agent-agnostic thread.
class AgentChatController extends ChangeNotifier {
  AgentChatController({
    required this.chatId,
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
    required this._secrets,
    required this._llmRuntime,
    required this._appSettings,
    this._brokerRegistry = BrokerExchangeRegistry.empty,
    this._favorites,
    this._mandate,
    this._investInterestProposals,
  });

  final String chatId;
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
  final EnvSecretsRepository _secrets;
  final LlmRuntimeSettings _llmRuntime;
  final AgentAppSettings _appSettings;
  final FavoritesRepository? _favorites;
  final MandateSettings? _mandate;
  final InvestInterestProposalRepository? _investInterestProposals;

  late final TradeProposalActions _proposalActions = TradeProposalActions(
    appSettings: _appSettings,
    proposals: _proposals,
    activity: _activity,
    tradeExecutor: _tradeExecutor,
  );

  InvestInterestProposalActions? get _investInterestActions {
    final repo = _investInterestProposals;
    final favorites = _favorites;
    final mandate = _mandate;
    if (repo == null || favorites == null || mandate == null) return null;
    return InvestInterestProposalActions(
      proposals: repo,
      activity: _activity,
      favorites: favorites,
      mandate: mandate,
    );
  }

  var _sending = false;
  var _actingOnProposal = false;

  bool get sending => _sending;
  bool get actingOnProposal => _actingOnProposal;

  bool get hasTradableExchange => _tradeExecutor.canTrade;

  bool get hasLlmEndpoint => LlmModelRouter.hasAnyEndpoint(
        runtime: _llmRuntime,
        keys: _secrets.llmKeys,
      );

  List<TradableVenue> get tradableVenues => _proposalActions.tradableVenues;

  AgentChatThread get thread => _chats.threadFor(chatId);

  List<AgentRoleDefinition> get enabledRoles => [
        for (final r in _agents.availableRoles)
          if (_appSettings.isRoleEnabled(r.id)) r,
      ];

  String? preferredPortfolioId() => _proposalActions.preferredPortfolioId();

  bool get needsPortfolioPicker => _proposalActions.needsPortfolioPicker;

  String? resolveConfirmPortfolioId({String? targetPortfolioId}) =>
      _proposalActions.resolveConfirmPortfolioId(
        targetPortfolioId: targetPortfolioId,
      );

  String resolveTargetExchangeId() =>
      _proposalActions.resolveTargetExchangeId();

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

  Future<AgentChatSendResult> sendStarter({
    required String roleId,
    String symbol = '',
    String? exchangeId,
    String? side,
    double? quantity,
  }) {
    if (roleId == 'intradayTrading' && !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }
    final sym = symbol.trim();
    if (sym.isEmpty && !AgentRolePrompts.allowsRunWithoutSymbol(roleId)) {
      return Future.value(
        const AgentChatSendFailed('Enter a symbol to Run.'),
      );
    }
    if (roleId == 'liveBalanceExplainer' &&
        resolveLiveBalanceExchangeId(exchangeId) == null) {
      return Future.value(
        const AgentChatSendFailed(
          'Connect a live exchange under Settings → Data sources to explain '
          'balances.',
        ),
      );
    }
    final prompt = AgentRolePrompts.runUserPrompt(
      roleId: roleId,
      symbol: sym,
      side: side,
      quantity: quantity,
    );
    return sendUserMessage(
      content: prompt,
      kind: AgentChatMessageKind.run,
      symbolHint: sym.isEmpty ? null : sym,
      exchangeId: exchangeId,
      activityRoleId: roleId,
    );
  }

  Future<AgentChatSendResult> sendRun({
    String symbol = '',
    String? exchangeId,
    String? side,
    double? quantity,
    String roleId = 'marketResearch',
  }) =>
      sendStarter(
        roleId: roleId,
        symbol: symbol,
        exchangeId: exchangeId,
        side: side,
        quantity: quantity,
      );

  Future<AgentChatSendResult> _blockNoExchange() async {
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.runBlockedNoExchange,
        roleId: 'intradayTrading',
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
    String? activityRoleId,
  }) async {
    if (!hasLlmEndpoint) {
      return const AgentChatSendBlockedNoLlm();
    }

    final endpoint = LlmModelRouter.resolve(
      weight: ModelWeight.light,
      runtime: _llmRuntime,
      keys: _secrets.llmKeys,
    );
    if (endpoint == null) {
      return const AgentChatSendBlockedNoLlm();
    }

    final liveExplainId = resolveLiveBalanceExchangeId(exchangeId);
    final stampedId =
        _tradeExecutor.canTrade ? resolveTargetExchangeId() : null;

    final userMessage = AgentChatMessage(
      id: AgentChatMessage.newId(),
      role: AgentChatRole.user,
      content: content,
      createdAt: DateTime.now().toUtc(),
      kind: kind,
    );
    await _chats.append(chatId: chatId, message: userMessage);
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.messageSent,
        roleId: activityRoleId ?? 'orchestrator',
        createdAt: DateTime.now().toUtc(),
        exchangeId: stampedId ?? liveExplainId,
        messageId: userMessage.id,
        symbol: symbolHint?.trim().toUpperCase(),
        summary:
            content.length > 120 ? '${content.substring(0, 117)}…' : content,
      ),
    );

    _sending = true;
    notifyListeners();

    try {
      final hint = symbolHint?.trim();
      LiveVenueCapabilities? liveVenue;
      if (liveExplainId != null) {
        liveVenue = _clientForExchange(liveExplainId);
      } else if (stampedId != null &&
          stampedId != PortfolioDescriptor.practiceId) {
        liveVenue = _clientForExchange(stampedId);
      }

      InvestInterestProposal? pendingInvestInterest;
      final investInterestRepo = _investInterestProposals;
      final toolDeps = OmniscopeAgentToolDeps(
        marketData: _marketData,
        practice: _portfolio.state,
        liveVenue: liveVenue,
        symbolHint: hint,
        investInterestSymbols:
            _favorites?.investInterestSymbols ?? const [],
        mandate: _mandate,
        answerMood: _appSettings.answerMood,
        answerMoodNote: _appSettings.answerMoodNote,
        proposeInvestInterest: investInterestRepo != null
            ? ({
                required List<String> add,
                required List<String> remove,
                List<String>? setSymbols,
                required String rationale,
              }) async {
                final proposal = InvestInterestProposal.fromToolInput(
                  {
                    'add': add,
                    'remove': remove,
                    'set': ?setSymbols,
                    'rationale': rationale,
                  },
                  roleId: activityRoleId ?? 'orchestrator',
                  chatId: chatId,
                );
                await investInterestRepo.upsert(proposal);
                pendingInvestInterest = proposal;
                await _activity.add(
                  AgentActivityEvent(
                    id: AgentActivityEvent.newId(),
                    kind: AgentActivityKind.investInterestProposed,
                    roleId: proposal.roleId,
                    createdAt: DateTime.now().toUtc(),
                    proposalId: proposal.id,
                    summary: proposal.summaryLabel,
                  ),
                );
                return 'Proposed Invest interest change '
                    '(pending Confirm in this chat): '
                    '${proposal.summaryLabel}. '
                    'Do not claim the list already changed.';
              }
            : null,
      );

      final specialties = [
        for (final role in enabledRoles)
          GenkitSpecialtySpec(
            roleId: role.id,
            description: AgentPeerDelegation.peerDescription(
              roleId: role.id,
              catalogDescription: role.description,
            ),
            workload: role.workload,
            modelIdOverride: _appSettings.overrideFor(role.id)?.modelId,
          ),
      ];

      final thread = _chats.threadFor(chatId);
      final stopwatch = Stopwatch()..start();
      final result = await _agentRunner.complete(
        endpoint: endpoint,
        messages: thread.messages,
        toolDeps: toolDeps,
        specialties: specialties,
        runtime: _llmRuntime,
      );
      stopwatch.stop();
      final reply = result.reply;

      final assistantId = AgentChatMessage.newId();
      TradeProposal? proposal;
      final tradeJson = result.delegatedTradeJson;
      if (tradeJson != null && stampedId != null && _tradeExecutor.canTrade) {
        final tradeRoleId = result.delegatedTradeRoleId ?? 'intradayTrading';
        proposal = TradeProposal.fromLlmJson(
          tradeJson,
          roleId: tradeRoleId,
          exchangeId: stampedId,
          chatId: chatId,
          sourceMessageId: assistantId,
          fallbackSymbol: hint,
        );
        await _proposals.upsert(proposal);
        await _activity.add(
          AgentActivityEvent(
            id: AgentActivityEvent.newId(),
            kind: AgentActivityKind.proposalParsed,
            roleId: tradeRoleId,
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

      if (pendingInvestInterest == null && investInterestRepo != null) {
        final iiJson = InvestInterestProposalParser.extractJsonMap(reply);
        if (iiJson != null) {
          final ii = InvestInterestProposal.fromToolInput(
            iiJson,
            roleId: activityRoleId ?? 'orchestrator',
            chatId: chatId,
            sourceMessageId: assistantId,
          );
          if (ii.isActionable) {
            await investInterestRepo.upsert(ii);
            pendingInvestInterest = ii;
            await _activity.add(
              AgentActivityEvent(
                id: AgentActivityEvent.newId(),
                kind: AgentActivityKind.investInterestProposed,
                roleId: ii.roleId,
                createdAt: DateTime.now().toUtc(),
                proposalId: ii.id,
                messageId: assistantId,
                summary: ii.summaryLabel,
              ),
            );
          }
        }
      }

      if (pendingInvestInterest != null &&
          investInterestRepo != null &&
          (pendingInvestInterest!.sourceMessageId == null ||
              pendingInvestInterest!.chatId == null)) {
        pendingInvestInterest = pendingInvestInterest!.copyWith(
          chatId: chatId,
          sourceMessageId: assistantId,
        );
        await investInterestRepo.upsert(pendingInvestInterest!);
      }

      await _chats.append(
        chatId: chatId,
        message: AgentChatMessage(
          id: assistantId,
          role: AgentChatRole.assistant,
          content: reply,
          createdAt: DateTime.now().toUtc(),
          proposalId: proposal?.id ?? pendingInvestInterest?.id,
          modelId: endpoint.modelId,
          generationMs: stopwatch.elapsedMilliseconds,
        ),
      );

      if (proposal != null &&
          _appSettings.autopilotEnabled &&
          proposal.isActionable) {
        await _maybeAutopilot(proposal);
        proposal = _proposals.byId(proposal.id) ?? proposal;
      }

      return AgentChatSendOk(
        proposal: proposal,
        investInterestProposal: pendingInvestInterest,
      );
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

  Future<void> _maybeAutopilot(TradeProposal proposal) async {
    final targetId = preferredPortfolioId();
    if (targetId == null) return;
    final mandateCap = _mandate?.maxOpenProposals;
    final maxOpen = mandateCap != null
        ? (_appSettings.autopilotMaxOpenProposals < mandateCap
            ? _appSettings.autopilotMaxOpenProposals
            : mandateCap)
        : _appSettings.autopilotMaxOpenProposals;
    final pending = _proposals.pendingForRole(proposal.roleId);
    if (pending.length > maxOpen) {
      await _proposals.upsert(
        proposal.copyWith(status: TradeProposalStatus.skipped),
      );
      return;
    }
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.autopilotSubmitted,
        roleId: proposal.roleId,
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

  Future<String?> confirmInvestInterestProposal(String proposalId) async {
    final actions = _investInterestActions;
    if (actions == null) {
      return 'Invest interest is not available.';
    }
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await actions.confirm(proposalId);
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<String?> dismissInvestInterestProposal(String proposalId) async {
    final actions = _investInterestActions;
    if (actions == null) {
      return 'Invest interest is not available.';
    }
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await actions.dismiss(proposalId);
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<void> clearThread() => _chats.clearThread(chatId);
}
