import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_role_prompts.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';

void main() {
  group('TradeProposalLlmSchema', () {
    test('canonical keys match trading role system prompts', () {
      const keys = TradeProposalLlmSchema.canonicalLlmKeys;
      expect(
        keys,
        ['ticker', 'action', 'quantity', 'rationale', 'risk_approved'],
      );
      for (final roleId in ['intradayTrading']) {
        final system = AgentRolePrompts.forRoleId(roleId);
        for (final key in keys) {
          expect(system, contains('"$key"'), reason: '$roleId missing $key');
        }
      }
    });

    test('intraday prompts require fractional crypto sizing vs cash', () {
      final system = AgentRolePrompts.forRoleId('intradayTrading');
      expect(system, contains('"quantity":0.01'));
      expect(system, contains('fractional'));
      expect(system, contains('BTC_USD'));
      expect(system, contains('fits available cash'));
      expect(system, isNot(contains('"quantity":0,')));
      expect(
        system,
        contains('cannot buy 1 whole BTC'),
      );
    });

    test('intraday prompts require Invest interest chart scan and pre-trade eval',
        () {
      final system = AgentRolePrompts.forRoleId('intradayTrading');
      expect(system, contains('getInvestInterest'));
      expect(system, contains('getHistory'));
      expect(system, contains('Invest interest'));
      expect(system, contains('nested-delegate'));
      expect(system, contains('Market Research'));
      expect(system, contains('risk_approved=true'));
      expect(system, contains('action=hold'));

      final orch = AgentRolePrompts.orchestratorSystem(
        specialtyRoleIds: const ['marketResearch', 'intradayTrading'],
      );
      expect(orch, contains('prefer the trading specialty'));
      expect(orch, contains('Invest interest charts'));
      expect(orch, contains('nested-delegate'));
    });
  });
}
