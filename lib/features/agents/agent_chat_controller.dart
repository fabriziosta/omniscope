import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_fleet_status.dart';
import '../../data/agents/agent_memory.dart';
import '../../data/agents/agent_memory_repository.dart';
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
import '../../data/agents/llm_connection_health.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/market_context_builder.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/fresh_market_data_client.dart';
import '../../data/market/market_data_client.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../data/trading/trade_proposal_actions.dart';
import '../../data/venues/live_venue_capabilities.dart';
import 'agent_chat_proposal_coordinator.dart';

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
  const AgentChatSendFailed(
    this.message, {
    this.connectionKind,
  });

  final String message;

  /// When set, UI can nudge Settings → Agents for auth failures.
  final LlmConnectionKind? connectionKind;

  bool get suggestConnections =>
      connectionKind == LlmConnectionKind.invalidKey;
}

class AgentChatSendBlockedNoExchange extends AgentChatSendResult {
  const AgentChatSendBlockedNoExchange();
}

class AgentChatSendBlockedNoLlm extends AgentChatSendResult {
  const AgentChatSendBlockedNoLlm();
}

/// Screen-scoped chat send / confirm for one agent-agnostic thread.
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
    this._agentMemory,
    this._investInterestProposals,
    this._scheduleInFlight,
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
  final AgentMemoryRepository? _agentMemory;
  final InvestInterestProposalRepository? _investInterestProposals;

  /// Optional Schedule batch in-flight probe (UI / coordinator).
  final bool Function()? _scheduleInFlight;

  late final TradeProposalActions _proposalActions = TradeProposalActions(
    appSettings: _appSettings,
    proposals: _proposals,
    activity: _activity,
    tradeExecutor: _tradeExecutor,
    marketData: _marketData,
    portfolio: _portfolio,
    chats: _chats,
  );

  late final AgentChatProposalCoordinator _proposalCoordinator =
      AgentChatProposalCoordinator(
    proposalActions: _proposalActions,
    chatId: chatId,
    activity: _activity,
    chats: _chats,
    investInterestProposals: _investInterestProposals,
    favorites: _favorites,
  );

  var _sendingCount = 0;
  var _actingOnProposal = false;

  bool get sending => _sendingCount > 0;
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
          if (thread.agentSettings.isRoleEnabled(r.id)) r,
      ];

  String? preferredPortfolioId() =>
      _proposalActions.preferredPortfolioId(chatId: chatId);

  bool get needsPortfolioPicker =>
      _proposalActions.needsPortfolioPicker(chatId: chatId);

  String? resolveConfirmPortfolioId({String? targetPortfolioId}) =>
      _proposalActions.resolveConfirmPortfolioId(
        targetPortfolioId: targetPortfolioId,
        chatId: chatId,
      );

  String resolveTargetExchangeId() =>
      _proposalActions.resolveTargetExchangeId(chatId: chatId);

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
    if (trimmed.isEmpty || sending) {
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
    String? content,
  }) async {
    if (roleId == 'intradayTrading' && !_tradeExecutor.canTrade) {
      return _blockNoExchange();
    }
    final override = content?.trim() ?? '';
    final placeholderError = override.isEmpty
        ? null
        : AgentRolePrompts.unresolvedDraftPlaceholderMessage(
            roleId: roleId,
            text: override,
          );
    if (placeholderError != null) {
      return AgentChatSendFailed(placeholderError);
    }
    final sym = symbol.trim();
    final prompt = override.isNotEmpty
        ? override
        : AgentRolePrompts.runUserPrompt(
            roleId: roleId,
            symbol: sym,
            side: side,
            quantity: quantity,
          );
    // Prefer a ticker from the (possibly edited) message; fall back to [symbol].
    final hint = MarketContextBuilder.extractSymbolHint(prompt) ??
        (sym.isNotEmpty ? sym.toUpperCase() : null);
    if ((hint == null || hint.isEmpty) &&
        !AgentRolePrompts.allowsRunWithoutSymbol(roleId)) {
      return const AgentChatSendFailed('Enter a symbol to Run.');
    }
    if (roleId == 'liveBalanceExplainer' &&
        resolveLiveBalanceExchangeId(exchangeId) == null) {
      return const AgentChatSendFailed(
        'Connect a live exchange under Settings → Data sources to explain '
        'balances.',
      );
    }

    var messageContent = prompt;
    MarketDataClient? turnMarket;
    if (hint != null && hint.isNotEmpty) {
      turnMarket = FreshMarketDataClient.forAgentTurn(_marketData);
      final snapshot = await MarketContextBuilder(turnMarket).buildForSymbol(
        hint,
      );
      if (snapshot != null && snapshot.isNotEmpty) {
        messageContent = '$snapshot\n\n---\n\n$prompt';
      }
    }

    return sendUserMessage(
      content: messageContent,
      kind: AgentChatMessageKind.run,
      symbolHint: hint,
      exchangeId: exchangeId,
      activityRoleId: roleId,
      agentMarketData: turnMarket,
    );
  }

  Future<AgentChatSendResult> sendRun({
    String symbol = '',
    String? exchangeId,
    String? side,
    double? quantity,
    String roleId = 'marketResearch',
    String? content,
  }) =>
      sendStarter(
        roleId: roleId,
        symbol: symbol,
        exchangeId: exchangeId,
        side: side,
        quantity: quantity,
        content: content,
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
    MarketDataClient? agentMarketData,
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

    _sendingCount++;
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
      final thread = _chats.threadFor(chatId);
      final chatAutopilot = thread.autopilotEnabled;
      final chatMemory = thread.memoryEnabled;
      final memoryRepo = chatMemory ? _agentMemory : null;
      final turnMarket =
          agentMarketData ?? FreshMarketDataClient.forAgentTurn(_marketData);
      final toolDeps = OmniscopeAgentToolDeps(
        marketData: turnMarket,
        practice: _portfolio.state,
        liveVenue: liveVenue,
        symbolHint: hint,
        investInterestSymbols:
            _favorites?.investInterestSymbols ?? const [],
        focusSymbols: thread.focusSymbols,
        mandate: thread.mandate,
        answerMood: thread.agentSettings.answerMood,
        answerMoodNote: thread.agentSettings.answerMoodNote,
        autopilotEnabled: chatAutopilot,
        memoryEnabled: chatMemory,
        memorySummary: memoryRepo?.toAgentSummary(),
        rememberFact: memoryRepo != null
            ? (text) => memoryRepo.addFact(
                  text,
                  source: AgentMemorySource.agent,
                )
            : null,
        forgetFact: memoryRepo != null
            ? (idOrText) => memoryRepo.removeFact(idOrText)
            : null,
        getFleetStatus: () => AgentFleetStatus.build(
              threads: _chats.threads,
              app: _appSettings,
              tradeProposals: _proposals.proposals,
              investInterestProposals:
                  investInterestRepo?.proposals ?? const [],
              mandate: thread.mandate,
              now: DateTime.now().toUtc(),
              scheduleRunning: _scheduleInFlight?.call() ?? false,
              currentChatId: chatId,
            ).toAgentSummary(),
        setChatAutopilot: ({required bool enabled}) async {
          if (enabled) {
            final block = _chats.autopilotEnableBlockReason(chatId);
            if (block != null) return block;
          }
          final next = await _chats.setAutopilotEnabled(
            chatId,
            enabled: enabled,
          );
          if (enabled && !next.autopilotEnabled) {
            return _chats.autopilotEnableBlockReason(chatId) ??
                'Could not enable Autopilot.';
          }
          if (enabled) {
            final applied = await applyPendingAutopilotInvestInterest();
            if (applied > 0) {
              return 'Autopilot ON for this chat (pinned). Applied $applied '
                  'pending Invest interest '
                  '${applied == 1 ? 'add' : 'adds'}.';
            }
            return 'Autopilot ON for this chat (pinned). Risk-approved trades '
                'and add-only Invest interest may apply without Confirm.';
          }
          return 'Autopilot OFF for this chat. Confirm is required again.';
        },
        pinChatSymbols: (symbols) async {
          final next = await _chats.pinFocusSymbols(chatId, symbols);
          return next.focusSymbols;
        },
        unpinChatSymbols: (symbols) async {
          final next = await _chats.unpinFocusSymbols(chatId, symbols);
          return next.focusSymbols;
        },
        tradeProposals: _proposals.proposals,
        chatId: chatId,
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
                await _pinFocusFromInvestInterest(proposal);
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
                final mayAutopilot =
                    _chats.threadFor(chatId).autopilotEnabled &&
                        InvestInterestProposalActions
                            .isAutopilotAddOnlyEligible(
                          proposal,
                        );
                return mayAutopilot
                    ? 'Proposed Invest interest add '
                        '(Autopilot may apply without Confirm): '
                        '${proposal.summaryLabel}.'
                    : 'Proposed Invest interest change '
                        '(pending Confirm — user must tap Confirm under '
                        'the proposal card in this chat, not reply in text '
                        'or use Activity): ${proposal.summaryLabel}. '
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

      final stopwatch = Stopwatch()..start();
      final result = await _agentRunner.complete(
        endpoint: endpoint,
        messages: _chats.threadFor(chatId).messages,
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
        if (proposal.symbol.trim().isNotEmpty) {
          await _chats.pinFocusSymbols(chatId, [proposal.symbol]);
        }
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
            await _pinFocusFromInvestInterest(ii);
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

      final selectedRoleIds = result.delegatedRoleIds.isNotEmpty
          ? result.delegatedRoleIds
          : const ['orchestrator'];

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
          specialtyRoleIds: selectedRoleIds,
        ),
      );

      // Re-read: setChatAutopilot may have enabled Autopilot mid-turn.
      final autopilotNow = _chats.threadFor(chatId).autopilotEnabled;

      if (proposal != null &&
          autopilotNow &&
          proposal.isActionable) {
        await _maybeAutopilot(proposal);
        proposal = _proposals.byId(proposal.id) ?? proposal;
      }

      if (pendingInvestInterest != null &&
          autopilotNow &&
          InvestInterestProposalActions.isAutopilotAddOnlyEligible(
            pendingInvestInterest!,
          )) {
        await _maybeAutopilotInvestInterest(pendingInvestInterest!);
        pendingInvestInterest =
            _investInterestProposals?.byId(pendingInvestInterest!.id) ??
                pendingInvestInterest;
      }

      return AgentChatSendOk(
        proposal: proposal,
        investInterestProposal: pendingInvestInterest,
      );
    } on GenkitAgentException catch (e) {
      return AgentChatSendFailed(
        e.message,
        connectionKind: e.connectionKind ??
            LlmConnectionHealth.classify(
              statusCode: e.statusCode,
              message: e.message,
            ),
      );
    } catch (e, st) {
      debugPrint('Agent chat send failed: $e\n$st');
      final classified = LlmConnectionHealth.fromError(e);
      return AgentChatSendFailed(
        classified.message,
        connectionKind: classified.kind,
      );
    } finally {
      _sendingCount = (_sendingCount - 1).clamp(0, 1 << 30);
      notifyListeners();
    }
  }

  Future<void> _maybeAutopilot(TradeProposal proposal) async {
    final targetId = preferredPortfolioId();
    if (targetId == null) return;
    final mandateCap = _chats.threadFor(chatId).mandate.maxOpenProposals;
    final maxOpen = _appSettings.autopilotMaxOpenProposals < mandateCap
        ? _appSettings.autopilotMaxOpenProposals
        : mandateCap;
    final pending = _proposals.pendingForRole(proposal.roleId);
    if (pending.length > maxOpen) {
      await _proposals.upsert(
        proposal.copyWith(status: TradeProposalStatus.skipped),
      );
      return;
    }
    final railError = await _proposalActions.evaluateRiskRails(
      proposal,
      autopilot: true,
    );
    if (railError != null) {
      await _proposals.upsert(
        proposal.copyWith(status: TradeProposalStatus.skipped),
      );
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: AgentActivityKind.autopilotSubmitted,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          exchangeId: targetId,
          proposalId: proposal.id,
          symbol: proposal.symbol,
          summary: railError,
        ),
      );
      if (railError.contains('daily realized loss')) {
        await _chats.setAutopilotEnabled(chatId, enabled: false);
      }
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

  Future<void> _maybeAutopilotInvestInterest(
    InvestInterestProposal proposal,
  ) async {
    await _proposalCoordinator.confirmInvestInterestProposal(
      proposal.id,
      autopilot: true,
    );
  }

  Future<void> _pinFocusFromInvestInterest(
    InvestInterestProposal proposal,
  ) async {
    final symbols = <String>[
      ...proposal.add,
      if (proposal.setSymbols != null) ...proposal.setSymbols!,
    ];
    if (symbols.isEmpty) return;
    await _chats.pinFocusSymbols(chatId, symbols);
  }

  Future<String?> confirmProposal(
    String proposalId, {
    bool autopilot = false,
    String? targetPortfolioId,
  }) async {
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalCoordinator.confirmProposal(
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
      return await _proposalCoordinator.dismissProposal(proposalId);
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<String?> confirmInvestInterestProposal(
    String proposalId, {
    bool autopilot = false,
  }) async {
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalCoordinator.confirmInvestInterestProposal(
        proposalId,
        autopilot: autopilot,
      );
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  Future<String?> dismissInvestInterestProposal(String proposalId) async {
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalCoordinator.dismissInvestInterestProposal(
        proposalId,
      );
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

  /// When Autopilot turns on for this chat, apply pending add-only Invest
  /// interest proposals (same rules as apply-at-send).
  Future<int> applyPendingAutopilotInvestInterest() async {
    _actingOnProposal = true;
    notifyListeners();
    try {
      return await _proposalCoordinator.applyPendingAutopilotInvestInterest();
    } finally {
      _actingOnProposal = false;
      notifyListeners();
    }
  }

}
