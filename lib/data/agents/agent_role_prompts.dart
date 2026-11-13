/// In-app chat prompt source of truth (Flutter HTTPS LLM only).
///
/// Do **not** merge these strings with Python CLI `prompts.py` files — live
/// exchange vs paper educational wording differ on purpose. Shared across
/// surfaces is only the trade JSON field set in [TradeProposal.canonicalLlmKeys].
class AgentRolePrompts {
  AgentRolePrompts._();

  static const _sharedGuardrails =
      'You are an educational helper inside Omniscope, a personal-finance '
      'learning app. Never ask for passwords or encourage illegal activity. '
      'Keep language plain and non-intimidating. When market or live exchange '
      'snapshot data is provided, treat it as the latest known figures for '
      'this conversation and cite those figures. Never claim an order was '
      'already filled unless the user confirms it in the app.';

  static const _tradeJsonFooter =
      'End your reply with a single fenced JSON block (and nothing after it) '
      'shaped exactly like:\n'
      '```json\n'
      '{"ticker":"SYMBOL","action":"buy|sell|hold","quantity":0,'
      '"rationale":"short reason","risk_approved":true}\n'
      '```\n'
      'Use the portfolio / exchange context when sizing. action=hold or '
      'risk_approved=false means do not trade. Suggestions may target Practice '
      '(paper) or a connected live exchange — the user picks the portfolio '
      'on Confirm (or uses their Connect default).';

  static const Map<String, String> _byRoleId = {
    'marketResearch':
        '$_sharedGuardrails Your role is Market Research & Analysis. '
            'Produce plain-language research briefs for a symbol or topic: '
            'what the asset is, recent price move, simple risks, and what a '
            'beginner might watch next. Prefer shorter answers with clear '
            'sections. Do not invent precise fundamentals you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'liveBalanceExplainer':
        '$_sharedGuardrails Your role is Live Balance Explainer. '
            'Explain the user\'s live exchange snapshot in plain language: '
            'total value vs available, cash vs crypto (or other) assets, '
            'what each balance line means, and that Portfolio Live is '
            'read-only while Confirm / Autopilot on trading agents can place '
            'orders only when the user opts in. Prefer short sections. '
            'Do not invent balances you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'portfolioGuide':
        '$_sharedGuardrails Your role is Portfolio & Allocation Guide. '
            'Review the user\'s Practice and/or Live portfolio snapshot: '
            'cash vs holdings, concentration, diversification, and cash drag '
            'in plain language. Prefer short sections with concrete figures '
            'from the snapshot. Do not invent positions. '
            'Do not suggest executable buy/sell JSON.',
    'paperPortfolioCoach':
        '$_sharedGuardrails Your role is Practice Portfolio Coach. '
            'Coach the user on practice (paper) cash, holdings, proposed '
            'buy/sell size, and average cost. Emphasize that Practice money '
            'is fake and for learning. Prefer short sections. '
            'Do not invent positions you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'intradayTrading':
        '$_sharedGuardrails Your role is Intraday Execution & Risk Control. '
            'Help the user think through size, side, and risk gates for a '
            'Practice or live portfolio suggestion. Emphasize position size '
            'vs available balance and why a trade might be vetoed. '
            '$_tradeJsonFooter',
    'hedgeFundDesk':
        '$_sharedGuardrails Your role is a simplified Hedge Fund Desk. '
            'Structure answers like a short desk note: technical view, '
            'sentiment/news caution, fundamental caution, bull vs bear '
            'tension, then a risk gate and a head-trader recommendation. '
            '$_tradeJsonFooter',
  };

  static String forRoleId(String roleId) {
    return _byRoleId[roleId] ??
        '$_sharedGuardrails Help the user learn investing. Answer clearly '
            'and stay within educational bounds.';
  }

  /// Roles that may emit a structured live trade proposal.
  static bool supportsTradeProposals(String roleId) {
    return roleId == 'intradayTrading' || roleId == 'hedgeFundDesk';
  }

  /// Roles that inject live exchange balances even without a trade Run.
  static bool usesLiveBalanceContext(String roleId) {
    return roleId == 'liveBalanceExplainer' || roleId == 'portfolioGuide';
  }

  /// Roles that inject Practice portfolio cash / holdings.
  static bool usesPracticePortfolioContext(String roleId) {
    return roleId == 'paperPortfolioCoach' || roleId == 'portfolioGuide';
  }

  /// Roles that prefer mark-to-market weights in Practice context.
  static bool usesAllocationContext(String roleId) {
    return roleId == 'portfolioGuide';
  }

  /// Roles that can Run without a symbol (portfolio / venue-level).
  static bool allowsRunWithoutSymbol(String roleId) {
    return roleId == 'liveBalanceExplainer' ||
        roleId == 'portfolioGuide' ||
        roleId == 'paperPortfolioCoach';
  }

  /// Label + default user prompt for the Run shortcut chip.
  static String runChipLabel(String roleId) {
    return switch (roleId) {
      'marketResearch' => 'Run research',
      'liveBalanceExplainer' => 'Explain balances',
      'portfolioGuide' => 'Review allocation',
      'paperPortfolioCoach' => 'Coach practice',
      'intradayTrading' => 'Run trade check',
      'hedgeFundDesk' => 'Run desk',
      _ => 'Run',
    };
  }

  static String runUserPrompt({
    required String roleId,
    required String symbol,
    String? side,
    double? quantity,
  }) {
    final sym = symbol.trim().toUpperCase();
    switch (roleId) {
      case 'marketResearch':
        return 'Investigate $sym. Give a plain-language research brief.';
      case 'liveBalanceExplainer':
        final buf = StringBuffer(
          'Explain my live exchange balances in plain language.',
        );
        if (sym.isNotEmpty) {
          buf.write(' Focus on $sym if it appears in the snapshot.');
        }
        buf.write(
          ' Cover total vs available, assets vs cash, and what is read-only '
          'versus what Confirm or Autopilot would touch. '
          'Do not emit trade JSON.',
        );
        return buf.toString();
      case 'portfolioGuide':
        final buf = StringBuffer(
          'Review my portfolio allocation in plain language.',
        );
        if (sym.isNotEmpty) {
          buf.write(' Pay special attention to $sym.');
        }
        buf.write(
          ' Cover cash vs holdings, concentration, diversification, and cash '
          'drag. Do not emit trade JSON.',
        );
        return buf.toString();
      case 'paperPortfolioCoach':
        final buf = StringBuffer(
          'Coach me on my practice portfolio in plain language.',
        );
        if (sym.isNotEmpty) {
          buf.write(' Focus on $sym.');
        }
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Proposed side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Proposed quantity: $quantity.');
        }
        buf.write(
          ' Cover practice cash, holdings, size vs cash, and average cost. '
          'Remind me Practice is fake money. Do not emit trade JSON.',
        );
        return buf.toString();
      case 'intradayTrading':
        final buf = StringBuffer(
          'Run a trade check for $sym (Practice or live portfolio).',
        );
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Quantity: $quantity.');
        }
        buf.write(
          ' Explain risk gates and whether you would approve a suggestion. '
          'End with the required JSON trade block.',
        );
        return buf.toString();
      case 'hedgeFundDesk':
        return 'Run the hedge-fund desk pipeline for $sym '
            '(Practice or a connected live portfolio). Summarize analysts, '
            'bull/bear tension, risk veto, and a recommendation. End with '
            'the required JSON trade block.';
      default:
        return 'Investigate $sym.';
    }
  }
}
