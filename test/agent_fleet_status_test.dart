import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_fleet_status.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/invest_interest_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';

import 'support/memory_config.dart';

TradeProposal _pendingTrade({
  required String id,
  required String symbol,
  String chatId = 'c1',
}) {
  return TradeProposal(
    id: id,
    roleId: 'intradayTrading',
    exchangeId: 'practice',
    symbol: symbol,
    side: TradeProposalSide.buy,
    quantity: 1,
    rationale: 't',
    riskApproved: true,
    status: TradeProposalStatus.pending,
    createdAt: DateTime.utc(2026, 11, 23),
    chatId: chatId,
  );
}

TradeProposal _autopilotFill({
  required String id,
  required DateTime filledAt,
  double? realizedPnl,
}) {
  return TradeProposal(
    id: id,
    roleId: 'intradayTrading',
    exchangeId: 'practice',
    symbol: 'AAPL',
    side: TradeProposalSide.sell,
    quantity: 1,
    rationale: 't',
    riskApproved: true,
    status: TradeProposalStatus.executed,
    createdAt: filledAt,
    chatId: 'c_ap',
    autopilot: true,
    fillPrice: 100,
    fillNotional: 100,
    filledAt: filledAt,
    realizedPnl: realizedPnl,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentFleetStatus', () {
    test('summary covers Autopilot, Schedule, pending, and rails', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();
      await app.setSchedule(
        enabled: true,
        symbols: const ['SPY'],
        scheduleChatId: 'c_sched',
      );
      await app.updateScheduleLastRunAt(DateTime.utc(2026, 11, 23, 10));

      final mandate = MandateSettings(store: store);
      await mandate.load();
      await mandate.setMaxAutopilotFillsPerDay(8);
      await mandate.setMaxDailyRealizedLoss(250);

      final now = DateTime.utc(2026, 11, 23, 12);
      final status = AgentFleetStatus.build(
        threads: [
          AgentChatThread(
            chatId: 'c_ap',
            title: 'Trade check AAPL',
            messages: const [],
            updatedAt: now,
            autopilotEnabled: true,
          ),
          AgentChatThread(
            chatId: 'c_sched',
            title: 'Scheduled run',
            messages: const [],
            updatedAt: now,
          ),
          AgentChatThread(
            chatId: 'c_idle',
            title: 'Idle chat',
            messages: const [],
            updatedAt: now,
          ),
        ],
        app: app,
        tradeProposals: [
          _pendingTrade(id: 'tp1', symbol: 'AAPL'),
          _pendingTrade(id: 'tp2', symbol: 'AAPL'),
          _pendingTrade(id: 'tp3', symbol: 'MSFT'),
          _autopilotFill(
            id: 'ex1',
            filledAt: DateTime.utc(2026, 11, 23, 11),
            realizedPnl: -12.5,
          ),
        ],
        investInterestProposals: [
          InvestInterestProposal(
            id: 'ii1',
            roleId: 'marketResearch',
            add: const ['NVDA', 'AAPL'],
            remove: const [],
            rationale: 'watch',
            status: InvestInterestProposalStatus.pending,
            createdAt: now,
          ),
        ],
        mandate: mandate,
        now: now,
        scheduleRunning: true,
        currentChatId: 'c_ap',
      );

      final text = status.toAgentSummary();
      expect(text, contains('Agent fleet status'));
      expect(text, contains('Autopilot on (1/5)'));
      expect(text, contains('Trade check AAPL [c_ap] (this chat)'));
      expect(text, isNot(contains('Idle chat')));
      expect(text, contains('Schedule: running'));
      expect(text, contains('Scheduled run [c_sched]'));
      expect(text, contains('Pending Confirm: 3 trade(s) (top: AAPL, MSFT)'));
      expect(text, contains('1 Invest interest change(s) (top: AAPL, NVDA)'));
      expect(text, contains('Autopilot fills today (UTC): 1 / 8'));
      expect(text, contains('Realized P&L today (UTC): \$-12.50'));
      expect(text, contains('loss stop \$250.00'));
      expect(text, isNot(contains('hello user message')));
    });

    test('empty Autopilot and Schedule off', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();

      final text = AgentFleetStatus.build(
        threads: const [],
        app: app,
        tradeProposals: const [],
        now: DateTime.utc(2026, 11, 23),
      ).toAgentSummary();

      expect(text, contains('Autopilot chats: none (0/5)'));
      expect(text, contains('Schedule: off'));
      expect(text, contains('Pending Confirm: 0 trade(s)'));
      expect(text, contains('no daily loss stop'));
    });

    test('Schedule ETA when not running', () async {
      final store = await memoryConfig();
      final app = AgentAppSettings(store: store);
      await app.load();
      await app.setSchedule(
        enabled: true,
        symbols: const ['SPY'],
        scheduleChatId: 'c_sched',
      );
      await app.updateScheduleLastRunAt(DateTime.utc(2026, 11, 23, 10));

      final text = AgentFleetStatus.build(
        threads: [
          AgentChatThread(
            chatId: 'c_sched',
            title: 'Scheduled run',
            messages: const [],
            updatedAt: DateTime.utc(2026, 11, 23),
          ),
        ],
        app: app,
        tradeProposals: const [],
        now: DateTime.utc(2026, 11, 23, 10, 15),
        scheduleRunning: false,
      ).toAgentSummary();

      expect(text, contains('Schedule: enabled'));
      expect(text, isNot(contains('running')));
      expect(text, contains('Next in'));
    });
  });

  group('AgentRolePrompts.fleetStatusPreamble', () {
    test('shown when Autopilot or Memory on; hidden when both off', () {
      expect(
        AgentRolePrompts.fleetStatusPreamble(memoryEnabled: true),
        contains('getAgentFleetStatus'),
      );
      expect(
        AgentRolePrompts.fleetStatusPreamble(
          autopilotEnabled: true,
          memoryEnabled: false,
        ),
        contains('getAgentFleetStatus'),
      );
      expect(
        AgentRolePrompts.fleetStatusPreamble(
          autopilotEnabled: false,
          memoryEnabled: false,
        ),
        isEmpty,
      );
      expect(
        AgentRolePrompts.forRoleId('marketResearch'),
        contains('getAgentFleetStatus'),
      );
    });
  });
}
