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
  });
}
