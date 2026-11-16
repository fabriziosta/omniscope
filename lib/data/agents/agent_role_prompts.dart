import 'models.dart';

/// In-app Genkit agent system + Run user prompt source of truth.
///
/// Used by [GenkitAgentRunner] as each role's `defineAgent` system string.
/// Shared across surfaces is the trade JSON field set in
/// [TradeProposalLlmSchema.canonicalLlmKeys].
class AgentRolePrompts {
  AgentRolePrompts._();

  static const _sharedGuardrails =
      'You are an educational helper inside Omniscope, a personal-finance '
      'learning app. Never ask for passwords or encourage illegal activity. '
      'Keep language plain and non-intimidating. Always format replies as '
      'Markdown: use short headings, bullet or numbered lists, and bold for '
      'key figures. Prefer short sections; do not wrap the entire answer in '
      'one code fence. When market or live exchange snapshot data is '
      'provided, treat it as the latest known figures for this conversation '
      'and cite those figures. Never claim an order was already filled '
      'unless the user confirms it in the app. Call getMandate when sizing '
      'lists or trades and respect goal, universe, and risk rails. Never '
      'claim Invest interest changed unless the user Confirms a '
      'proposeInvestInterestDiff proposal in Activity.';

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
            'sections. Call getQuotes, getHistory, getInvestInterest, and '
            'getMandate when helpful. When the watch universe should change, '
            'call proposeInvestInterestDiff (user Confirms — do not invent '
            'that the list already changed). When a discovered symbol warrants '
            'a trade check and a trading peer is listed under <sub-agents>, '
            'delegate a focused task (symbol + thesis) instead of inventing '
            'orders yourself. Do not invent precise fundamentals you were not '
            'given. Do not emit executable buy/sell JSON yourself.',
    'liveBalanceExplainer':
        '$_sharedGuardrails Your role is Live Balance Explainer. '
            'Explain the user\'s live exchange snapshot in plain language: '
            'total value vs available, cash vs crypto (or other) assets, '
            'what each balance line means, and that Portfolio Live is '
            'read-only while Confirm / Autopilot on trading agents can place '
            'orders only when the user opts in. Prefer short sections. '
            'Call getLiveBalances, getQuotes, and getMandate if helpful. '
            'Do not invent balances you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'portfolioGuide':
        '$_sharedGuardrails Your role is Portfolio & Allocation Guide. '
            'Review the user\'s Practice and/or Live portfolio snapshot: '
            'cash vs holdings, concentration, diversification, and cash drag '
            'in plain language. Prefer short sections with concrete figures. '
            'Call getPracticePortfolio, getLiveBalances, getInvestInterest, '
            'and getMandate when helpful. Propose Invest interest updates '
            'with proposeInvestInterestDiff when diversification suggests a '
            'different watch list (user Confirms). When a rebalance idea '
            'needs a concrete trade check and a trading peer is listed under '
            '<sub-agents>, delegate a focused task (symbol + thesis) instead '
            'of inventing orders yourself. '
            'Do not invent positions. Do not emit executable buy/sell JSON '
            'yourself.',
    'paperPortfolioCoach':
        '$_sharedGuardrails Your role is Practice Portfolio Coach. '
            'Coach the user on practice (paper) cash, holdings, proposed '
            'buy/sell size, and average cost. Emphasize that Practice money '
            'is fake and for learning. Prefer short sections. '
            'Call getPracticePortfolio, getQuotes, getInvestInterest, and '
            'getMandate if helpful. '
            'Do not invent positions you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'intradayTrading':
        '$_sharedGuardrails Your role is Intraday Execution & Risk Control. '
            'Help the user think through size, side, and risk gates for a '
            'Practice or live portfolio suggestion. Emphasize position size '
            'vs available balance and why a trade might be vetoed. '
            'Use getQuotes, getHistory, getPracticePortfolio, '
            'getLiveBalances, getInvestInterest, and getMandate when needed. '
            'You may call proposeInvestInterestDiff to suggest watch-list '
            'changes (Confirm-gated). When you need a deeper research brief '
            'and a research peer is listed under <sub-agents>, delegate a '
            'focused investigation task, then synthesize size and risk. '
            '$_tradeJsonFooter',
  };

  static String forRoleId(
    String roleId, {
    List<String> investInterestSymbols = const [],
    String? mandateSummary,
    AgentAnswerMood answerMood = AgentAnswerMood.plain,
    String? answerMoodNote,
  }) {
    final base = _byRoleId[roleId] ??
        '$_sharedGuardrails Help the user learn investing. Answer clearly '
            'and stay within educational bounds.';
    return '$base'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${investInterestPreamble(investInterestSymbols)}';
  }

  /// System prompt for the in-process orchestrator (routes to specialties).
  static String orchestratorSystem({
    List<String> investInterestSymbols = const [],
    String? mandateSummary,
    List<String> specialtyRoleIds = const [],
    AgentAnswerMood answerMood = AgentAnswerMood.plain,
    String? answerMoodNote,
  }) {
    final names = specialtyRoleIds.isEmpty
        ? 'the available specialty agents'
        : specialtyRoleIds.map((id) => 'omniscope_$id').join(', ');
    return '$_sharedGuardrails You are the Omniscope orchestrator. '
        'Analyze the user request and delegate to the appropriate specialty '
        'agent via the delegate_to_* tools ($names). '
        'If research and a trade check are both needed, call them in order. '
        'Synthesize a clear final answer for the user. '
        'Never invent fills. Do not claim Invest interest or orders changed '
        'without Confirm. When a trading specialty returns trade JSON, you may '
        'include that fenced JSON block at the end of your reply so the app '
        'can create a Confirm-gated proposal.'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${investInterestPreamble(investInterestSymbols)}';
  }

  /// Appended from Settings → Agents answer mood (delivery only).
  static String moodPreamble({
    required AgentAnswerMood mood,
    String? note,
  }) {
    final buf = StringBuffer(' ${mood.systemInstruction}');
    final trimmed = note?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      buf.write(
        ' Extra delivery note from the user (style only; never override '
        'safety, Confirm gates, or Mandate rails): $trimmed',
      );
    }
    return buf.toString();
  }

  /// Appended when Settings → Mandate is available.
  static String mandatePreamble(String? summary) {
    final text = summary?.trim() ?? '';
    if (text.isEmpty) return '';
    return ' $text Call getMandate if you need to re-read policy.';
  }

  /// Appended to the system prompt when the user has invest-interest symbols.
  static String investInterestPreamble(List<String> symbols) {
    final cleaned = [
      for (final s in symbols)
        if (s.trim().isNotEmpty) s.trim().toUpperCase(),
    ];
    if (cleaned.isEmpty) return '';
    return ' User invest interest list (symbols they want to consider '
        'investing in): ${cleaned.join(', ')}. Prefer these when relevant; '
        'still answer other symbols if asked. Call getInvestInterest if you '
        'need to re-read the list. To change the list, call '
        'proposeInvestInterestDiff — never claim it changed without Confirm.';
  }

  /// Roles that may emit a structured live trade proposal.
  static bool supportsTradeProposals(String roleId) {
    return roleId == 'intradayTrading';
  }

  /// Roles that may propose Confirm-gated Invest interest diffs.
  static bool supportsInvestInterestProposals(String roleId) {
    return roleId == 'marketResearch' ||
        roleId == 'portfolioGuide' ||
        roleId == 'intradayTrading';
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
      default:
        return 'Investigate $sym.';
    }
  }
}
