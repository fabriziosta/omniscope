import 'models.dart';

/// Why the user is opening an agent from another screen.
enum AgentLaunchIntent {
  /// Plain-language research / desk insight for a symbol.
  investigate,

  /// Paper trade size / risk check for a symbol.
  tradeCheck,

  /// Plain-language walkthrough of live exchange balances.
  explainLive,

  /// Allocation / diversification review (Practice and/or Live).
  explainPortfolio,

  /// Practice portfolio coaching (cash, size, avg cost).
  paperReview,
}

extension AgentLaunchIntentX on AgentLaunchIntent {
  /// Manifest role ids that can fulfill this intent (preferred order).
  List<String> get preferredRoleIds => switch (this) {
        AgentLaunchIntent.investigate => const [
            'marketResearch',
            'hedgeFundDesk',
          ],
        AgentLaunchIntent.tradeCheck => const [
            'intradayTrading',
            'hedgeFundDesk',
          ],
        AgentLaunchIntent.explainLive => const [
            'liveBalanceExplainer',
          ],
        AgentLaunchIntent.explainPortfolio => const [
            'portfolioGuide',
          ],
        AgentLaunchIntent.paperReview => const [
            'paperPortfolioCoach',
          ],
      };

  /// True when this intent can auto-run without a symbol.
  bool get isPortfolioLevel => switch (this) {
        AgentLaunchIntent.explainLive ||
        AgentLaunchIntent.explainPortfolio ||
        AgentLaunchIntent.paperReview =>
          true,
        _ => false,
      };

  /// Primary CTA label when a single button is shown.
  String get ctaLabel => switch (this) {
        AgentLaunchIntent.investigate => 'Investigate',
        AgentLaunchIntent.tradeCheck => 'Trade check',
        AgentLaunchIntent.explainLive => 'Explain balances',
        AgentLaunchIntent.explainPortfolio => 'Review allocation',
        AgentLaunchIntent.paperReview => 'Practice coach',
      };

  /// Short dialog title when picking among several roles.
  String get pickerTitle => switch (this) {
        AgentLaunchIntent.investigate => 'Investigate with',
        AgentLaunchIntent.tradeCheck => 'Trade check with',
        AgentLaunchIntent.explainLive => 'Explain balances with',
        AgentLaunchIntent.explainPortfolio => 'Review allocation with',
        AgentLaunchIntent.paperReview => 'Practice coach with',
      };
}

/// Resolves which catalog roles apply to an in-app launch intent.
class AgentLaunchResolver {
  AgentLaunchResolver._();

  /// Roles from [availableRoles] that match [intent], in preferred order.
  static List<AgentRoleDefinition> rolesForIntent({
    required List<AgentRoleDefinition> availableRoles,
    required AgentLaunchIntent intent,
  }) {
    final byId = <String, AgentRoleDefinition>{
      for (final r in availableRoles) r.id: r,
    };
    return [
      for (final id in intent.preferredRoleIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Connected subset of [roles], preserving order.
  static List<AgentRoleDefinition> connectedAmong({
    required List<AgentRoleDefinition> roles,
    required bool Function(String roleId) isConnected,
  }) {
    return [for (final r in roles) if (isConnected(r.id)) r];
  }
}
