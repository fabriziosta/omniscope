import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_robustness.dart';
import 'package:omniscope/data/agents/models.dart';

AgentRoleDefinition _role({
  required String id,
  required AgentFramework framework,
  required AgentWorkload workload,
}) {
  return AgentRoleDefinition(
    id: id,
    title: id,
    description: '',
    framework: framework,
    workload: workload,
    suggestedModels: const {},
  );
}

void main() {
  group('AgentRobustness', () {
    test('locked scores for current Genkit roles', () {
      // T derived from AgentToolRegistry ACL.
      // W8 + F14 + D14 + G0 + T5 (quotesOnly) = 41
      expect(
        AgentRobustness.score(
          _role(
            id: 'marketResearch',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        41,
      );
      // W8 + F14 + D14 + G0 + T10 (portfolioSnapshot) = 46
      expect(
        AgentRobustness.score(
          _role(
            id: 'liveBalanceExplainer',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        46,
      );
      // W8 + F14 + D14 + G0 + T15 (multiSource) = 51
      expect(
        AgentRobustness.score(
          _role(
            id: 'portfolioGuide',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        51,
      );
      // W20 + F14 + D14 + G20 + T15 (multiSource) = 83
      expect(
        AgentRobustness.score(
          _role(
            id: 'intradayTrading',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.trading,
          ),
        ),
        83,
      );
      // W8 + F14 + D14 + G0 + T5 (quotesOnly) = 41
      expect(
        AgentRobustness.score(
          _role(
            id: 'cryptoSpotGuide',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        41,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'marketsLiteracy',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        41,
      );
    });

    test('contextToolsForRole follows registry ACL', () {
      expect(
        AgentRobustness.contextToolsForRole('marketResearch'),
        AgentContextTools.quotesOnly,
      );
      expect(
        AgentRobustness.contextToolsForRole('liveBalanceExplainer'),
        AgentContextTools.portfolioSnapshot,
      );
      expect(
        AgentRobustness.contextToolsForRole('portfolioGuide'),
        AgentContextTools.multiSource,
      );
      expect(
        AgentRobustness.contextToolsForRole('intradayTrading'),
        AgentContextTools.multiSource,
      );
      expect(
        AgentRobustness.contextToolsForRole('cryptoSpotGuide'),
        AgentContextTools.quotesOnly,
      );
      expect(
        AgentRobustness.contextToolsForRole('marketsLiteracy'),
        AgentContextTools.quotesOnly,
      );
    });

    test('unknown role id uses defaults from workload and framework', () {
      expect(
        AgentRobustness.score(
          _role(
            id: 'futureUnknownRole',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.investigation,
          ),
        ),
        33, // W8 + F14 + D6 + G0 + T5
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'futureUnknownTrading',
            framework: AgentFramework.genkit,
            workload: AgentWorkload.trading,
          ),
        ),
        45, // W20 + F14 + D6 + G0 + T5
      );
    });

    test('clamp keeps score in 1–100', () {
      final mid = AgentRobustnessBreakdown(
        workload: 20,
        framework: 20,
        depth: 25,
        riskGates: 20,
        contextTools: 15,
      );
      expect(mid.score, 100);
      expect(mid.rawTotal, 100);

      const over = AgentRobustnessBreakdown(
        workload: 50,
        framework: 50,
        depth: 50,
        riskGates: 50,
        contextTools: 50,
      );
      expect(over.rawTotal, 250);
      expect(over.score, 100);

      const under = AgentRobustnessBreakdown(
        workload: 0,
        framework: 0,
        depth: 0,
        riskGates: 0,
        contextTools: 0,
      );
      expect(under.rawTotal, 0);
      expect(under.score, 1);
    });
  });
}
