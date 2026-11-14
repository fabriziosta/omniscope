import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/agents/agent_activity.dart';
import '../../data/agents/agent_activity_repository.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/genkit/genkit_agent_runner.dart';
import '../../data/agents/models.dart';
import '../../data/agents/trade_proposal.dart';
import '../../data/agents/trade_proposal_repository.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/notifications/app_notification.dart';
import '../../data/notifications/app_notification_repository.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/trading/trade_executor.dart';
import 'agent_chat_controller.dart';

/// Foreground-only scheduler: while Omniscope is open and resumed, polls
/// connected agents with [AgentConnection.scheduleEnabled] and Runs their
/// symbols via the same [AgentChatController.sendRun] path as chat.
///
/// Each completed (or failed) Run also enqueues a shell attention notification
/// so the user can open chat to Confirm or review Autopilot results.
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

  /// How often to check due schedules (not the user-facing Run interval).
  final Duration pollInterval;

  Timer? _timer;
  var _resumed = false;
  var _disposed = false;
  final _inFlight = <String>{};

  bool get isResumed => _resumed;
  bool get isPolling => _timer != null;

  /// Start (or resume) the poll loop. Safe to call repeatedly.
  void resume() {
    if (_disposed) return;
    _resumed = true;
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  /// Pause ticks while the app is backgrounded / tab hidden.
  void pause() {
    _resumed = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Test helper: mark resumed without starting the timer or catch-up tick.
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

  /// One poll: run every due connection that is not already in flight.
  ///
  /// Exposed for tests; production uses the periodic timer + [resume].
  Future<void> tick({DateTime? now}) async {
    if (_disposed || !_resumed) return;
    final at = now ?? DateTime.now().toUtc();
    final due = [
      for (final c in _agents.connections)
        if (c.isScheduleDue(at) && !_inFlight.contains(c.roleId)) c,
    ];
    for (final connection in due) {
      await _runBatch(connection, at);
      if (_disposed || !_resumed) return;
    }
  }

  Future<void> _runBatch(AgentConnection connection, DateTime at) async {
    final roleId = connection.roleId;
    final role = _agents.roleCatalog?.byId(roleId);
    if (role == null) return;

    final symbols = List<String>.from(connection.scheduleSymbols);
    if (symbols.isEmpty) return;

    _inFlight.add(roleId);
    try {
      // Stamp first so a crash mid-batch does not immediately re-fire.
      await _agents.updateScheduleLastRunAt(roleId, at);

      final controller = AgentChatController(
        role: role,
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
      );

      for (final symbol in symbols) {
        if (_disposed || !_resumed) break;
        // Re-check connection still wants scheduling.
        final latest = _agents.forRoleId(roleId);
        if (!latest.connected || !latest.scheduleEnabled) break;

        await _activity.add(
          AgentActivityEvent(
            id: AgentActivityEvent.newId(),
            kind: AgentActivityKind.scheduledRun,
            roleId: roleId,
            createdAt: DateTime.now().toUtc(),
            symbol: symbol,
            summary: 'Scheduled run · $symbol',
          ),
        );

        final result = await controller.sendRun(symbol: symbol);
        if (result is AgentChatSendFailed) {
          await _activity.add(
            AgentActivityEvent(
              id: AgentActivityEvent.newId(),
              kind: AgentActivityKind.scheduledRun,
              roleId: roleId,
              createdAt: DateTime.now().toUtc(),
              symbol: symbol,
              summary: 'Scheduled run failed · $symbol · ${result.message}',
            ),
          );
        }
        // Blocked / ok: sendRun already logged activity for exchange gates.

        await _enqueueNotification(
          roleTitle: role.title,
          roleId: roleId,
          symbol: symbol,
          result: result,
        );
      }

      controller.dispose();
    } finally {
      _inFlight.remove(roleId);
    }
  }

  Future<void> _enqueueNotification({
    required String roleTitle,
    required String roleId,
    required String symbol,
    required AgentChatSendResult result,
  }) async {
    final AppNotificationKind kind;
    final String title;
    final String body;
    String? proposalId;

    switch (result) {
      case AgentChatSendFailed(:final message):
        kind = AppNotificationKind.scheduledRunFailed;
        title = 'Scheduled run failed';
        body = '$roleTitle · $symbol · $message';
      case AgentChatSendBlockedNoExchange():
        kind = AppNotificationKind.scheduledRunFailed;
        title = 'Scheduled run blocked';
        body = '$roleTitle · $symbol · connect a tradable portfolio in Settings';
      case AgentChatSendOk(:final proposal):
        if (proposal == null) {
          kind = AppNotificationKind.scheduledRunCompleted;
          title = 'Scheduled run finished';
          body = '$roleTitle · $symbol';
        } else {
          proposalId = proposal.id;
          final autopilotStatuses = {
            TradeProposalStatus.executed,
            TradeProposalStatus.failed,
            TradeProposalStatus.skipped,
          };
          if (proposal.autopilot ||
              autopilotStatuses.contains(proposal.status)) {
            kind = AppNotificationKind.scheduledAutopilotDone;
            title = switch (proposal.status) {
              TradeProposalStatus.executed => 'Autopilot placed an order',
              TradeProposalStatus.failed => 'Autopilot order failed',
              TradeProposalStatus.skipped => 'Autopilot skipped a proposal',
              _ => 'Autopilot ran',
            };
            body =
                '$roleTitle · ${proposal.side.label} ${proposal.quantity} $symbol';
          } else if (proposal.status == TradeProposalStatus.pending) {
            kind = AppNotificationKind.scheduledProposalPending;
            title = 'Confirm a scheduled suggestion';
            body =
                '$roleTitle · ${proposal.side.label} ${proposal.quantity} $symbol';
          } else {
            kind = AppNotificationKind.scheduledRunCompleted;
            title = 'Scheduled run finished';
            body = '$roleTitle · $symbol';
          }
        }
    }

    await _notifications.enqueue(
      AppNotification(
        id: AppNotification.newId(),
        kind: kind,
        roleId: roleId,
        createdAt: DateTime.now().toUtc(),
        title: title,
        body: body,
        symbol: symbol,
        proposalId: proposalId,
      ),
    );
  }
}
