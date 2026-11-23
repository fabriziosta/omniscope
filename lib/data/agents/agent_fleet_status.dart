import '../settings/mandate_settings.dart';
import 'agent_app_settings.dart';
import 'agent_chat_repository.dart';
import 'agent_pnl_service.dart';
import 'chat_models.dart';
import 'invest_interest_proposal.dart';
import 'trade_proposal.dart';

/// One Autopilot-on chat listed in a fleet snapshot (no transcript).
class AgentFleetAutopilotChat {
  const AgentFleetAutopilotChat({
    required this.chatId,
    required this.title,
  });

  final String chatId;
  final String title;
}

/// Compact device-wide operational status for agents (no sibling transcripts).
class AgentFleetStatus {
  const AgentFleetStatus({
    required this.autopilotChats,
    required this.autopilotCap,
    required this.scheduleEnabled,
    this.scheduleChatId,
    this.scheduleChatTitle,
    this.scheduleRunning = false,
    this.scheduleEtaLabel,
    this.pendingTradeCount = 0,
    this.pendingInvestInterestCount = 0,
    this.topPendingTradeSymbols = const [],
    this.topPendingInvestSymbols = const [],
    this.autopilotFillsToday = 0,
    this.maxAutopilotFillsPerDay =
        MandateSettings.defaultMaxAutopilotFillsPerDay,
    this.realizedPnlToday = 0,
    this.maxDailyRealizedLoss,
    this.currentChatId,
  });

  final List<AgentFleetAutopilotChat> autopilotChats;
  final int autopilotCap;
  final bool scheduleEnabled;
  final String? scheduleChatId;
  final String? scheduleChatTitle;
  final bool scheduleRunning;
  final String? scheduleEtaLabel;
  final int pendingTradeCount;
  final int pendingInvestInterestCount;
  final List<String> topPendingTradeSymbols;
  final List<String> topPendingInvestSymbols;
  final int autopilotFillsToday;
  final int maxAutopilotFillsPerDay;
  final double realizedPnlToday;
  final double? maxDailyRealizedLoss;
  final String? currentChatId;

  static const maxTopSymbols = 5;

  /// Builds a snapshot from live repos (no message bodies).
  static AgentFleetStatus build({
    required List<AgentChatThread> threads,
    required AgentAppSettings app,
    required Iterable<TradeProposal> tradeProposals,
    Iterable<InvestInterestProposal> investInterestProposals = const [],
    MandateSettings? mandate,
    required DateTime now,
    bool scheduleRunning = false,
    String? currentChatId,
    int autopilotCap = AgentChatRepository.maxAutopilotEnabledChats,
  }) {
    final autopilot = <AgentFleetAutopilotChat>[
      for (final t in threads)
        if (t.autopilotEnabled)
          AgentFleetAutopilotChat(
            chatId: t.chatId,
            title: t.title.trim().isEmpty ? t.chatId : t.title.trim(),
          ),
    ];

    final pendingTrades = <TradeProposal>[
      for (final p in tradeProposals)
        if (p.status == TradeProposalStatus.pending &&
            p.side != TradeProposalSide.hold &&
            p.quantity > 0)
          p,
    ];
    final pendingIi = <InvestInterestProposal>[
      for (final p in investInterestProposals)
        if (p.isActionable) p,
    ];

    final scheduleId = app.scheduleChatId?.trim();
    String? scheduleTitle;
    if (scheduleId != null && scheduleId.isNotEmpty) {
      for (final t in threads) {
        if (t.chatId == scheduleId) {
          scheduleTitle =
              t.title.trim().isEmpty ? scheduleId : t.title.trim();
          break;
        }
      }
      scheduleTitle ??= scheduleId;
    }

    final fillsCap = mandate?.maxAutopilotFillsPerDay ??
        MandateSettings.defaultMaxAutopilotFillsPerDay;

    return AgentFleetStatus(
      autopilotChats: autopilot,
      autopilotCap: autopilotCap,
      scheduleEnabled: app.scheduleEnabled,
      scheduleChatId: scheduleId,
      scheduleChatTitle: scheduleTitle,
      scheduleRunning: scheduleRunning && app.scheduleEnabled,
      scheduleEtaLabel: app.scheduleEtaLabel(now),
      pendingTradeCount: pendingTrades.length,
      pendingInvestInterestCount: pendingIi.length,
      topPendingTradeSymbols: _topSymbols([
        for (final p in pendingTrades) p.symbol,
      ]),
      topPendingInvestSymbols: _topSymbols([
        for (final p in pendingIi) ...p.add,
        for (final p in pendingIi) ...?p.setSymbols,
      ]),
      autopilotFillsToday: AgentPnlService.autopilotFillCountForUtcDay(
        proposals: tradeProposals,
        now: now,
      ),
      maxAutopilotFillsPerDay: fillsCap,
      realizedPnlToday: AgentPnlService.realizedPnlForUtcDay(
        proposals: tradeProposals,
        now: now,
      ),
      maxDailyRealizedLoss: mandate?.maxDailyRealizedLoss,
      currentChatId: currentChatId?.trim(),
    );
  }

  /// Plain-text block for the `getAgentFleetStatus` tool (capped, no transcripts).
  String toAgentSummary() {
    final lines = <String>[
      'Agent fleet status (operational only — no other chat messages):',
    ];

    final current = currentChatId?.trim() ?? '';
    if (autopilotChats.isEmpty) {
      lines.add(
        '- Autopilot chats: none (0/$autopilotCap).',
      );
    } else {
      final labels = [
        for (final c in autopilotChats)
          '${c.title} [${c.chatId}]'
              '${c.chatId == current ? ' (this chat)' : ''}',
      ];
      lines.add(
        '- Autopilot on (${autopilotChats.length}/$autopilotCap): '
        '${labels.join('; ')}.',
      );
    }

    if (!scheduleEnabled) {
      lines.add('- Schedule: off.');
    } else {
      final home = scheduleChatTitle ?? scheduleChatId ?? 'linked chat';
      final homeId = scheduleChatId;
      final homeLabel = homeId == null
          ? home
          : '$home [$homeId]'
              '${homeId == current ? ' (this chat)' : ''}';
      if (scheduleRunning) {
        lines.add('- Schedule: running on $homeLabel.');
      } else {
        final eta = scheduleEtaLabel?.trim();
        lines.add(
          '- Schedule: enabled on $homeLabel'
          '${eta == null || eta.isEmpty ? '' : ' · $eta'}.',
        );
      }
    }

    final tradeSym = topPendingTradeSymbols.isEmpty
        ? ''
        : ' (top: ${topPendingTradeSymbols.join(', ')})';
    final iiSym = topPendingInvestSymbols.isEmpty
        ? ''
        : ' (top: ${topPendingInvestSymbols.join(', ')})';
    lines.add(
      '- Pending Confirm: $pendingTradeCount trade(s)$tradeSym; '
      '$pendingInvestInterestCount Invest interest change(s)$iiSym.',
    );

    lines.add(
      '- Autopilot fills today (UTC): $autopilotFillsToday / '
      '$maxAutopilotFillsPerDay.',
    );

    final pnl = realizedPnlToday.toStringAsFixed(2);
    final lossCap = maxDailyRealizedLoss;
    if (lossCap != null && lossCap > 0) {
      lines.add(
        '- Realized P&L today (UTC): \$$pnl '
        '(loss stop \$${lossCap.toStringAsFixed(2)}).',
      );
    } else {
      lines.add('- Realized P&L today (UTC): \$$pnl (no daily loss stop).');
    }

    lines.add(
      'Use this to avoid duplicating work another Autopilot or Schedule '
      'chat is already handling. Do not claim sibling chat contents.',
    );
    return lines.join('\n');
  }

  static List<String> _topSymbols(Iterable<String> raw) {
    final counts = <String, int>{};
    for (final s in raw) {
      final sym = s.trim().toUpperCase();
      if (sym.isEmpty) continue;
      counts[sym] = (counts[sym] ?? 0) + 1;
    }
    final ordered = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.compareTo(b);
      });
    if (ordered.length <= maxTopSymbols) return ordered;
    return ordered.sublist(0, maxTopSymbols);
  }
}
