import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/invest_interest_proposal.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Activity operation delete', () {
    test('trade proposal delete removes the row and linked events', () async {
      final store = await memoryConfig();
      final proposals = TradeProposalRepository(store: store);
      final activity = AgentActivityRepository(store: store);
      await proposals.load();
      await activity.load();

      const id = 'tp_delete_1';
      await proposals.upsert(
        TradeProposal(
          id: id,
          roleId: 'intradayTrading',
          exchangeId: 'practice',
          symbol: 'AAPL',
          side: TradeProposalSide.buy,
          quantity: 1,
          rationale: 'test',
          riskApproved: true,
          status: TradeProposalStatus.executed,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await activity.add(
        AgentActivityEvent(
          id: 'ev_1',
          kind: AgentActivityKind.proposalParsed,
          roleId: 'intradayTrading',
          createdAt: DateTime.utc(2026, 1, 1),
          proposalId: id,
          summary: 'parsed',
        ),
      );
      await activity.add(
        AgentActivityEvent(
          id: 'ev_keep',
          kind: AgentActivityKind.messageSent,
          roleId: 'intradayTrading',
          createdAt: DateTime.utc(2026, 1, 2),
          summary: 'unrelated',
        ),
      );

      expect(await proposals.delete(id), isTrue);
      expect(await proposals.delete(id), isFalse);
      expect(proposals.byId(id), isNull);
      expect(await activity.deleteForProposal(id), 1);
      expect(activity.forProposal(id), isEmpty);
      expect(activity.events.single.id, 'ev_keep');
    });

    test('invest interest proposal delete removes the row', () async {
      final store = await memoryConfig();
      final proposals = InvestInterestProposalRepository(store: store);
      await proposals.load();

      const id = 'ii_delete_1';
      await proposals.upsert(
        InvestInterestProposal(
          id: id,
          roleId: 'marketResearch',
          add: const ['MSFT'],
          remove: const [],
          rationale: 'watch',
          status: InvestInterestProposalStatus.confirmed,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(await proposals.delete(id), isTrue);
      expect(proposals.byId(id), isNull);
      expect(await proposals.delete('missing'), isFalse);
    });
  });
}
