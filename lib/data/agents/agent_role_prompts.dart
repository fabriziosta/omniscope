/// Educational system prompts keyed by manifest role id.
class AgentRolePrompts {
  AgentRolePrompts._();

  static const _sharedGuardrails =
      'You are an educational helper inside Omniscope, a personal-finance '
      'learning app. This is paper / educational context only — never claim '
      'to place real brokerage orders, never ask for passwords, and never '
      'encourage illegal activity. Keep language plain and non-intimidating. '
      'When market snapshot data is provided, treat it as the latest known '
      'prices for this conversation and cite those figures.';

  static const Map<String, String> _byRoleId = {
    'marketResearch':
        '$_sharedGuardrails Your role is Market Research & Analysis. '
            'Produce plain-language research briefs for a symbol or topic: '
            'what the asset is, recent price move, simple risks, and what a '
            'beginner might watch next. Prefer shorter answers with clear '
            'sections. Do not invent precise fundamentals you were not given.',
    'intradayTrading':
        '$_sharedGuardrails Your role is Intraday Execution & Risk Control '
            '(paper). Help the user think through size, side, and risk gates '
            'for educational trades. Emphasize position size vs cash, stop '
            'thinking, and why a paper trade might be vetoed. Never present '
            'output as a live order confirmation.',
    'hedgeFundDesk':
        '$_sharedGuardrails Your role is a simplified Hedge Fund Desk '
            '(paper). Structure answers like a short desk note: technical '
            'view, sentiment/news caution, fundamental caution, bull vs bear '
            'tension, then a risk gate and a paper head-trader recommendation '
            '(ticker, action, quantity rationale, risk_approved true/false). '
            'Stay educational; no broker API claims.',
  };

  static String forRoleId(String roleId) {
    return _byRoleId[roleId] ??
        '$_sharedGuardrails Help the user learn investing. Answer clearly '
            'and stay within paper-trading / educational bounds.';
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
        final buf = StringBuffer('Run a paper trade check for $sym.');
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Quantity: $quantity.');
        }
        buf.write(
          ' Explain risk gates and whether you would approve on paper.',
        );
        return buf.toString();
      case 'hedgeFundDesk':
        return 'Run the paper hedge-fund desk pipeline for $sym. '
            'Summarize analysts, bull/bear tension, risk veto, and a paper '
            'recommendation.';
      default:
        return 'Investigate $sym.';
    }
  }
}
