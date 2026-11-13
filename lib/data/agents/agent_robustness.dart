import 'models.dart';

/// Pipeline stage count band for [AgentRobustness] depth points.
enum AgentPipelineDepth {
  /// Single-stage / one-shot role.
  one,

  /// Two or three stages.
  twoToThree,

  /// Four to six stages.
  fourToSix,

  /// Seven or more stages (e.g. Hedge Fund Desk).
  sevenPlus,
}

/// Risk-control strength for [AgentRobustness] gate points.
enum AgentRiskGates {
  none,
  soft,
  hardVeto,
}

/// Market / portfolio context breadth for [AgentRobustness] tool points.
enum AgentContextTools {
  quotesOnly,
  portfolioSnapshot,
  multiSource,
}

/// Optional architecture overrides that are not fully encoded in the manifest
/// (hybrid framework, depth, gates, tools).
class AgentArchitectureProfile {
  const AgentArchitectureProfile({
    required this.depth,
    required this.riskGates,
    required this.contextTools,
    this.hybridFramework = false,
  });

  final AgentPipelineDepth depth;
  final AgentRiskGates riskGates;
  final AgentContextTools contextTools;

  /// When true, framework points use the hybrid (LangGraph + CrewAI) band.
  final bool hybridFramework;
}

/// Factor breakdown for tests and tooltips.
class AgentRobustnessBreakdown {
  const AgentRobustnessBreakdown({
    required this.workload,
    required this.framework,
    required this.depth,
    required this.riskGates,
    required this.contextTools,
  });

  final int workload;
  final int framework;
  final int depth;
  final int riskGates;
  final int contextTools;

  int get rawTotal =>
      workload + framework + depth + riskGates + contextTools;

  int get score {
    final t = rawTotal;
    if (t < 1) return 1;
    if (t > 100) return 100;
    return t;
  }
}

/// Computed 1–100 robustness score (pipeline complexity + risk controls).
///
/// Higher is more complex / more gated — not “better advice” or live reliability.
class AgentRobustness {
  AgentRobustness._();

  static const tooltipMessage =
      'Robustness — pipeline complexity and risk controls (1–100).';

  /// Known role architecture profiles (depth / gates / tools / hybrid).
  static const Map<String, AgentArchitectureProfile> profiles = {
    'marketResearch': AgentArchitectureProfile(
      depth: AgentPipelineDepth.one,
      riskGates: AgentRiskGates.none,
      contextTools: AgentContextTools.quotesOnly,
    ),
    'liveBalanceExplainer': AgentArchitectureProfile(
      depth: AgentPipelineDepth.one,
      riskGates: AgentRiskGates.none,
      contextTools: AgentContextTools.portfolioSnapshot,
    ),
    'portfolioGuide': AgentArchitectureProfile(
      depth: AgentPipelineDepth.one,
      riskGates: AgentRiskGates.none,
      contextTools: AgentContextTools.portfolioSnapshot,
    ),
    'paperPortfolioCoach': AgentArchitectureProfile(
      depth: AgentPipelineDepth.one,
      riskGates: AgentRiskGates.none,
      contextTools: AgentContextTools.portfolioSnapshot,
    ),
    'intradayTrading': AgentArchitectureProfile(
      depth: AgentPipelineDepth.twoToThree,
      riskGates: AgentRiskGates.hardVeto,
      contextTools: AgentContextTools.portfolioSnapshot,
    ),
    'hedgeFundDesk': AgentArchitectureProfile(
      depth: AgentPipelineDepth.sevenPlus,
      riskGates: AgentRiskGates.hardVeto,
      contextTools: AgentContextTools.multiSource,
      hybridFramework: true,
    ),
  };

  static const AgentArchitectureProfile _defaultProfile =
      AgentArchitectureProfile(
    depth: AgentPipelineDepth.one,
    riskGates: AgentRiskGates.none,
    contextTools: AgentContextTools.quotesOnly,
  );

  static AgentArchitectureProfile profileFor(String roleId) =>
      profiles[roleId] ?? _defaultProfile;

  static int score(AgentRoleDefinition role) => breakdown(role).score;

  static AgentRobustnessBreakdown breakdown(AgentRoleDefinition role) {
    final profile = profileFor(role.id);
    return AgentRobustnessBreakdown(
      workload: _workloadPoints(role.workload),
      framework: _frameworkPoints(role.framework, profile),
      depth: _depthPoints(profile.depth),
      riskGates: _riskGatePoints(profile.riskGates),
      contextTools: _contextToolPoints(profile.contextTools),
    );
  }

  static int _workloadPoints(AgentWorkload workload) => switch (workload) {
        AgentWorkload.investigation => 8,
        AgentWorkload.trading => 20,
      };

  static int _frameworkPoints(
    AgentFramework framework,
    AgentArchitectureProfile profile,
  ) {
    if (profile.hybridFramework) return 20;
    return switch (framework) {
      AgentFramework.crewAi => 8,
      AgentFramework.langGraph => 16,
    };
  }

  static int _depthPoints(AgentPipelineDepth depth) => switch (depth) {
        AgentPipelineDepth.one => 6,
        AgentPipelineDepth.twoToThree => 14,
        AgentPipelineDepth.fourToSix => 20,
        AgentPipelineDepth.sevenPlus => 25,
      };

  static int _riskGatePoints(AgentRiskGates gates) => switch (gates) {
        AgentRiskGates.none => 0,
        AgentRiskGates.soft => 10,
        AgentRiskGates.hardVeto => 20,
      };

  static int _contextToolPoints(AgentContextTools tools) => switch (tools) {
        AgentContextTools.quotesOnly => 5,
        AgentContextTools.portfolioSnapshot => 10,
        AgentContextTools.multiSource => 15,
      };
}
