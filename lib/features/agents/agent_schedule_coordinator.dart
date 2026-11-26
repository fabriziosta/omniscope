import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_app_settings.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_memory_repository.dart';
import '../../data/agents/agent_role_prompts.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/genkit/genkit_agent_runner.dart';
import '../../data/agents/invest_interest_proposal_repository.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/agents/models.dart';
import '../../data/agents/schedule_chat_binding.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/fresh_market_data_client.dart';
import '../../data/market/market_data_client.dart';
import '../../data/notifications/app_notification.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/trading/trade_executor.dart';
import 'agent_chat_controller.dart';

/// Foreground-only scheduler: Runs invest-interest / symbols via orchestrator.
class AgentScheduleCoordinator extends ChangeNotifier {
  AgentScheduleCoordinator({
    required this._agents,
    required this._chats,
    required this._marketData,
    required this._agentRunner,
    required this._tradeExecutor,
    required this._proposals,
    required this._activity,
    required this._notifications,
    required this._cryptoRegistry,
    required this._dataSources,
    required this._portfolio,
    required this._favorites,
    required this._secrets,
    required this._llmRuntime,
    required this._appSettings,
    this._agentMemory,
    this._investInterestProposals,
    this.pollInterval = const Duration(seconds: 60),
  });

  final AgentsRepository _agents;
  final AgentChatRepository _chats;
  final MarketDataClient _marketData;
  final GenkitAgentRunner _agentRunner;
  final TradeExecutor _tradeExecutor;
  final TradeProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final AppNotificationRepository _notifications;
  final CryptoExchangeRegistry _cryptoRegistry;
  final DataSourceSettings _dataSources;
  final PortfolioRepository _portfolio;
  final FavoritesRepository _favorites;
  final EnvSecretsRepository _secrets;
  final LlmRuntimeSettings _llmRuntime;
  final AgentAppSettings _appSettings;
  final AgentMemoryRepository? _agentMemory;
  final InvestInterestProposalRepository? _investInterestProposals;

  final Duration pollInterval;

  static const _scheduleConcurrency = 2;

  Timer? _timer;
  var _resumed = false;
  var _disposed = false;
  var _inFlight = false;

  bool get isResumed => _resumed;
  bool get isPolling => _timer != null;
  bool get isInFlight => _inFlight;

  void resume() {
    if (_disposed) return;
    _resumed = true;
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void pause() {
    _resumed = false;
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  void debugMarkResumed() {
    if (_disposed) return;
    _resumed = true;
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }

  Future<void> tick({DateTime? now}) async {
    if (_disposed || !_resumed || _inFlight) return;
    final at = now ?? DateTime.now().toUtc();
    if (!_appSettings.isScheduleDue(at)) return;
    await _runBatch(at);
  }

  Future<void> _runBatch(DateTime at) async {
    final symbols = _appSettings.scheduleUseInvestInterest
        ? List<String>.from(_favorites.investInterestSymbols)
        : List<String>.from(_appSettings.scheduleSymbols);
    if (symbols.isEmpty) return;

    _inFlight = true;
    if (!_disposed) notifyListeners();
    try {
      final chat = await ScheduleChatBinding.ensureChat(
        app: _appSettings,
        chats: _chats,
      );
      final controller = AgentChatController(
        chatId: chat.chatId,
        agents: _agents,
        chats: _chats,
        marketData: _marketData,
        agentRunner: _agentRunner,
        tradeExecutor: _tradeExecutor,
        proposals: _proposals,
        activity: _activity,
        cryptoRegistry: _cryptoRegistry,
        dataSources: _dataSources,
        portfolio: _portfolio,
        secrets: _secrets,
        llmRuntime: _llmRuntime,
        appSettings: _appSettings,
        favorites: _favorites,
        agentMemory: _agentMemory,
        investInterestProposals: _investInterestProposals,
        scheduleInFlight: () => true,
      );

      final intervalLabel = _appSettings.scheduleInterval.shortLabel;
      final mandateSummary =
          _chats.threadFor(chat.chatId).mandate.toAgentSummary();
      final total = symbols.length;

      await _prewarmScheduleQuotes(symbols);

      // Runs stay sequential on one chat (append is not race-safe across
      // awaits). Quote prewarm above uses [_scheduleConcurrency]; activity /
      // notification writes coalesce once at the end of the batch.
      final activityEvents = <AgentActivityEvent>[];
      final notifications = <AppNotification>[];

      for (var i = 0; i < symbols.length; i++) {
        if (_disposed || !_resumed) break;
        if (!_appSettings.scheduleEnabled) break;

        final symbol = symbols[i];
        activityEvents.add(
          AgentActivityEvent(
            id: AgentActivityEvent.newId(),
            kind: AgentActivityKind.scheduledRun,
            roleId: 'orchestrator',
            createdAt: DateTime.now().toUtc(),
            symbol: symbol,
            summary: 'Scheduled run · $symbol',
          ),
        );

        final wake = AgentRolePrompts.scheduledRunUserPrompt(
          symbol: symbol,
          intervalLabel: intervalLabel,
          mandateSummary: mandateSummary,
          index: i + 1,
          total: total,
        );
        final result = await controller.sendRun(
          symbol: symbol,
          roleId: 'marketResearch',
          content: wake,
        );
        if (result is AgentChatSendFailed) {
          activityEvents.add(
            AgentActivityEvent(
              id: AgentActivityEvent.newId(),
              kind: AgentActivityKind.scheduledRun,
              roleId: 'orchestrator',
              createdAt: DateTime.now().toUtc(),
              symbol: symbol,
              summary: 'Scheduled run failed · $symbol · ${result.message}',
            ),
          );
        }

        final okResult = result is AgentChatSendOk ? result : null;
        final ok = okResult != null;
        final proposalId =
            okResult?.proposal?.id ?? okResult?.investInterestProposal?.id;
        if (proposalId == null) {
          notifications.add(
            AppNotification(
              id: AppNotification.newId(),
              kind: ok
                  ? AppNotificationKind.scheduledRunCompleted
                  : AppNotificationKind.scheduledRunFailed,
              roleId: 'orchestrator',
              createdAt: DateTime.now().toUtc(),
              title: 'Scheduled agent run',
              body: ok
                  ? 'Finished $symbol — open the chat to review.'
                  : 'Run for $symbol needs attention.',
              symbol: symbol,
              chatId: chat.chatId,
            ),
          );
        }
      }

      await _activity.addAll(activityEvents);
      await _notifications.enqueueAll(notifications);

      await _appSettings.updateScheduleLastRunAt(at);
    } finally {
      _inFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Warms the agent-turn quote cache before sequential per-symbol Runs.
  Future<void> _prewarmScheduleQuotes(List<String> symbols) async {
    final turnMarket = FreshMarketDataClient.forAgentTurn(_marketData);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= symbols.length) return;
        final sym = symbols[i].trim().toUpperCase();
        if (sym.isEmpty) continue;
        try {
          await turnMarket.getQuotes([sym]);
        } catch (_) {
          // Best-effort — sendRun still fetches on miss.
        }
      }
    }

    await Future.wait(
      List.generate(_scheduleConcurrency, (_) => worker()),
    );
  }
}
