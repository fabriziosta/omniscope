/// Educational system prompts keyed by manifest role id.
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
      'Use the live exchange context when sizing. action=hold or '
      'risk_approved=false means do not trade. Suggestions target a connected '
      'live exchange only — never paper practice money.';

  static const Map<String, String> _byRoleId = {
    'marketResearch':
        '$_sharedGuardrails Your role is Market Research & Analysis. '
            'Produce plain-language research briefs for a symbol or topic: '
            'what the asset is, recent price move, simple risks, and what a '
            'beginner might watch next. Prefer shorter answers with clear '
            'sections. Do not invent precise fundamentals you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'intradayTrading':
        '$_sharedGuardrails Your role is Intraday Execution & Risk Control. '
            'Help the user think through size, side, and risk gates for a '
            'live exchange suggestion. Emphasize position size vs available '
            'balance and why a trade might be vetoed. '
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

  /// Label + default user prompt for the Run shortcut chip.
  static String runChipLabel(String roleId) {
    return switch (roleId) {
      'marketResearch' => 'Run research',
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
      case 'intradayTrading':
        final buf = StringBuffer(
          'Run a live-exchange trade check for $sym.',
        );
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Quantity: $quantity.');
        }
        buf.write(
          ' Explain risk gates and whether you would approve a live suggestion. '
          'End with the required JSON trade block.',
        );
        return buf.toString();
      case 'hedgeFundDesk':
        return 'Run the hedge-fund desk pipeline for $sym on a connected '
            'live exchange. Summarize analysts, bull/bear tension, risk veto, '
            'and a recommendation. End with the required JSON trade block.';
      default:
        return 'Investigate $sym.';
    }
  }
}
