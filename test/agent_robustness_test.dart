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
    module: 'm',
    packagePath: 'p',
    workload: workload,
    suggestedModels: const {},
  );
}

void main() {
  group('AgentRobustness', () {
    test('locked scores for current roles', () {
      expect(
        AgentRobustness.score(
          _role(
            id: 'marketResearch',
            framework: AgentFramework.crewAi,
            workload: AgentWorkload.investigation,
          ),
        ),
        27,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'liveBalanceExplainer',
            framework: AgentFramework.crewAi,
            workload: AgentWorkload.investigation,
          ),
        ),
        32,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'portfolioGuide',
            framework: AgentFramework.crewAi,
            workload: AgentWorkload.investigation,
          ),
        ),
        32,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'paperPortfolioCoach',
            framework: AgentFramework.crewAi,
            workload: AgentWorkload.investigation,
          ),
        ),
        32,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'intradayTrading',
            framework: AgentFramework.langGraph,
            workload: AgentWorkload.trading,
          ),
        ),
        80,
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'hedgeFundDesk',
            framework: AgentFramework.langGraph,
            workload: AgentWorkload.trading,
          ),
        ),
        100,
      );
    });

    test('hedgeFundDesk uses hybrid framework points despite langGraph meta',
        () {
      final b = AgentRobustness.breakdown(
        _role(
          id: 'hedgeFundDesk',
          framework: AgentFramework.langGraph,
          workload: AgentWorkload.trading,
        ),
      );
      expect(b.workload, 20);
      expect(b.framework, 20);
      expect(b.depth, 25);
      expect(b.riskGates, 20);
      expect(b.contextTools, 15);
      expect(b.rawTotal, 100);
      expect(b.score, 100);
    });

    test('unknown role id uses defaults from workload and framework', () {
      expect(
        AgentRobustness.score(
          _role(
            id: 'futureUnknownRole',
            framework: AgentFramework.crewAi,
            workload: AgentWorkload.investigation,
          ),
        ),
        27, // W8 + F8 + D6 + G0 + T5
      );
      expect(
        AgentRobustness.score(
          _role(
            id: 'futureUnknownTrading',
            framework: AgentFramework.langGraph,
            workload: AgentWorkload.trading,
          ),
        ),
        47, // W20 + F16 + D6 + G0 + T5
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
