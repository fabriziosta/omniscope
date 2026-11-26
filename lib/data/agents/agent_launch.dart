import 'models.dart';

/// Why the user is opening an agent from another screen.
enum AgentLaunchIntent {
  /// Plain-language research / desk insight for a symbol.
  investigate,

  /// Agent trade size / risk check for a symbol (Confirm or Autopilot).
  tradeCheck,

  /// Plain-language walkthrough of live exchange balances.
  explainLive,

  /// Allocation / diversification / practice sizing review (Practice and/or Live).
  explainPortfolio,

  /// Crypto spot pair literacy (venue tickers, quote units).
  explainCryptoSpot,

  /// Markets instrument literacy (indices vs ETFs vs stocks).
  explainMarketsLiteracy,
}

extension AgentLaunchIntentX on AgentLaunchIntent {
  /// Manifest role ids that can fulfill this intent (preferred order).
  List<String> get preferredRoleIds => switch (this) {
        AgentLaunchIntent.investigate => const [
            'marketResearch',
          ],
        AgentLaunchIntent.tradeCheck => const [
            'intradayTrading',
          ],
        AgentLaunchIntent.explainLive => const [
            'liveBalanceExplainer',
          ],
        AgentLaunchIntent.explainPortfolio => const [
            'portfolioGuide',
          ],
        AgentLaunchIntent.explainCryptoSpot => const [
            'cryptoSpotGuide',
          ],
        AgentLaunchIntent.explainMarketsLiteracy => const [
            'marketsLiteracy',
          ],
      };

  /// True when this intent can auto-run without a symbol.
  bool get isPortfolioLevel => switch (this) {
        AgentLaunchIntent.explainLive ||
        AgentLaunchIntent.explainPortfolio =>
          true,
        _ => false,
      };

  /// True when this intent can draft without a required symbol.
  bool get allowsOptionalSymbol => switch (this) {
        AgentLaunchIntent.explainLive ||
        AgentLaunchIntent.explainPortfolio ||
        AgentLaunchIntent.explainCryptoSpot ||
        AgentLaunchIntent.explainMarketsLiteracy =>
          true,
        _ => false,
      };

  /// Primary CTA label when a single button is shown.
  String get ctaLabel => switch (this) {
        AgentLaunchIntent.investigate => 'Investigate',
        AgentLaunchIntent.tradeCheck => 'Trade check',
        AgentLaunchIntent.explainLive => 'Explain balances',
        AgentLaunchIntent.explainPortfolio => 'Review portfolio',
        AgentLaunchIntent.explainCryptoSpot => 'Spot primer',
        AgentLaunchIntent.explainMarketsLiteracy => 'Markets tutor',
      };

  /// Title for the new chat created when this intent is launched from a CTA.
  ///
  /// [symbol] is used for asset-scoped intents; [portfolioLabel] for portfolio
  /// intents (defaults to `Practice` when omitted).
  String chatTitle({String? symbol, String? portfolioLabel}) {
    final asset = symbol?.trim() ?? '';
    final portfolio = () {
      final label = portfolioLabel?.trim() ?? '';
      return label.isNotEmpty ? label : 'Practice';
    }();
    return switch (this) {
      AgentLaunchIntent.investigate =>
        asset.isNotEmpty ? 'Investigate asset $asset' : 'Investigate asset',
      AgentLaunchIntent.tradeCheck =>
        asset.isNotEmpty ? 'Trade check for $asset' : 'Trade check',
      AgentLaunchIntent.explainLive => 'Explain balances for $portfolio',
      AgentLaunchIntent.explainPortfolio =>
        'Portfolio review for $portfolio',
      AgentLaunchIntent.explainCryptoSpot => asset.isNotEmpty
          ? 'Crypto spot primer for $asset'
          : 'Crypto spot primer',
      AgentLaunchIntent.explainMarketsLiteracy => asset.isNotEmpty
          ? 'Markets tutor for $asset'
          : 'Markets tutor',
    };
  }
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
}
