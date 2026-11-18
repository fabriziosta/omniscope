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
      'lists or trades and respect goal, universe, and risk rails. For '
      'Invest interest, call proposeInvestInterestDiff; do not invent that '
      'the list already changed unless Autopilot add-only applied it.';

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
            'call proposeInvestInterestDiff (prefer add-only when Autopilot '
            'is on; remove/set still need Confirm). When a discovered symbol warrants '
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
            'cash vs holdings, concentration, diversification, cash drag, '
            'and (for Practice) proposed size vs cash and average cost. '
            'Emphasize that Practice money is fake and for learning. '
            'Prefer short sections with concrete figures. '
            'Call getPracticePortfolio, getLiveBalances, getQuotes, '
            'getInvestInterest, and getMandate when helpful. Propose Invest '
            'interest updates with proposeInvestInterestDiff when '
            'diversification suggests a different watch list (prefer '
            'add-only under Autopilot; remove/set still need Confirm). When '
            'a rebalance idea needs a concrete trade check and a trading '
            'peer is listed under <sub-agents>, delegate a focused task '
            '(symbol + thesis) instead of inventing orders yourself. '
            'Do not invent positions. Do not emit executable buy/sell JSON '
            'yourself.',
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
    bool autopilotEnabled = false,
  }) {
    final base = _byRoleId[roleId] ??
        '$_sharedGuardrails Help the user learn investing. Answer clearly '
            'and stay within educational bounds.';
    return '$base'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${investInterestPreamble(investInterestSymbols, autopilotEnabled: autopilotEnabled)}'
        '${autopilotPreamble(autopilotEnabled)}';
  }

  /// System prompt for the in-process orchestrator (routes to specialties).
  static String orchestratorSystem({
    List<String> investInterestSymbols = const [],
    String? mandateSummary,
    List<String> specialtyRoleIds = const [],
    AgentAnswerMood answerMood = AgentAnswerMood.plain,
    String? answerMoodNote,
    bool autopilotEnabled = false,
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
        'without Confirm (except Autopilot add-only Invest interest when '
        'enabled). When a trading specialty returns trade JSON, you may '
        'include that fenced JSON block at the end of your reply so the app '
        'can create a Confirm-gated proposal.'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${investInterestPreamble(investInterestSymbols, autopilotEnabled: autopilotEnabled)}'
        '${autopilotPreamble(autopilotEnabled)}';
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

  /// Appended when Autopilot is enabled (add-only Invest interest + trades).
  static String autopilotPreamble(bool enabled) {
    if (!enabled) return '';
    return ' Autopilot is ON: investigation add-only Invest interest '
        'proposals (add with empty remove, no set) from marketResearch / '
        'portfolioGuide may apply without Confirm. Prefer add-only diffs. '
        'remove/set still need Confirm. Risk-approved trade proposals may '
        'auto-submit to the default portfolio.';
  }

  /// Appended to the system prompt when the user has invest-interest symbols.
  static String investInterestPreamble(
    List<String> symbols, {
    bool autopilotEnabled = false,
  }) {
    final cleaned = [
      for (final s in symbols)
        if (s.trim().isNotEmpty) s.trim().toUpperCase(),
    ];
    if (cleaned.isEmpty) {
      if (!autopilotEnabled) return '';
      return ' Invest interest list is empty. To add symbols, call '
          'proposeInvestInterestDiff with add-only (Autopilot may apply).';
    }
    final gate = autopilotEnabled
        ? 'prefer add-only proposeInvestInterestDiff (Autopilot may apply '
            'adds; remove/set need Confirm)'
        : 'call proposeInvestInterestDiff — never claim it changed without '
            'Confirm';
    return ' User invest interest list (symbols they want to consider '
        'investing in): ${cleaned.join(', ')}. Prefer these when relevant; '
        'still answer other symbols if asked. Call getInvestInterest if you '
        'need to re-read the list. To change the list, $gate.';
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
    return roleId == 'portfolioGuide';
  }

  /// Roles that prefer mark-to-market weights in Practice context.
  static bool usesAllocationContext(String roleId) {
    return roleId == 'portfolioGuide';
  }

  /// Roles that can Run without a symbol (portfolio / venue-level).
  static bool allowsRunWithoutSymbol(String roleId) {
    return roleId == 'liveBalanceExplainer' || roleId == 'portfolioGuide';
  }

  /// Placeholder ticker shown in editable starter drafts for the user to replace.
  static const draftSymbolPlaceholder = 'SYMBOL';

  /// Placeholder side shown in trading / portfolio-review drafts.
  static const draftSidePlaceholder = 'buy|sell';

  /// Placeholder quantity shown in trading / portfolio-review drafts.
  static const draftQuantityPlaceholder = 'QUANTITY';

  /// Short title for a starter card / auto-run label.
  static String runChipLabel(String roleId) {
    return switch (roleId) {
      'marketResearch' => 'Market research',
      'liveBalanceExplainer' => 'Explain balances',
      'portfolioGuide' => 'Review portfolio',
      'intradayTrading' => 'Trade check',
      _ => 'Starter',
    };
  }

  /// One-line blurb under [runChipLabel] on selectable starter tiles.
  static String runChipDescription(String roleId) {
    return switch (roleId) {
      'marketResearch' => 'Plain-language brief for a symbol or topic',
      'liveBalanceExplainer' => 'Walk through live totals and balances',
      'portfolioGuide' =>
          'Allocation, concentration, and practice sizing',
      'intradayTrading' => 'Size, side, and risk before you Confirm',
      _ => 'Draft a prompt into the composer',
    };
  }

  /// Editable composer draft for a starter (placeholders for custom values).
  ///
  /// Prefer [symbol] / [side] / [quantity] when known; otherwise insert
  /// [draftSymbolPlaceholder] and related tokens the user can replace.
  static String runUserPromptDraft({
    required String roleId,
    String symbol = '',
    String? side,
    double? quantity,
  }) {
    final trimmed = symbol.trim();
    final needsSymbol = !allowsRunWithoutSymbol(roleId);
    // Intraday always drafts side/qty placeholders; portfolio guide only when
    // the launch already carries a proposed side or quantity (e.g. practice
    // trade card).
    final hasTradeHints = (side != null && side.trim().isNotEmpty) ||
        (quantity != null && quantity > 0);
    final withTradeExtras = roleId == 'intradayTrading' ||
        (roleId == 'portfolioGuide' && hasTradeHints);
    final sym = trimmed.isNotEmpty
        ? trimmed.toUpperCase()
        : (needsSymbol ? draftSymbolPlaceholder : '');
    final sideDraft = (side != null && side.trim().isNotEmpty)
        ? side.trim().toLowerCase()
        : (withTradeExtras ? draftSidePlaceholder : null);
    return runUserPrompt(
      roleId: roleId,
      symbol: sym,
      side: sideDraft,
      quantity: quantity != null && quantity > 0 ? quantity : null,
      quantityPlaceholder: withTradeExtras && (quantity == null || quantity <= 0)
          ? draftQuantityPlaceholder
          : null,
      forceOptionalSymbolPlaceholder:
          allowsRunWithoutSymbol(roleId) && trimmed.isEmpty,
    );
  }

  static String runUserPrompt({
    required String roleId,
    required String symbol,
    String? side,
    double? quantity,
    String? quantityPlaceholder,
    bool forceOptionalSymbolPlaceholder = false,
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
        } else if (forceOptionalSymbolPlaceholder) {
          buf.write(
            ' Focus on $draftSymbolPlaceholder if it appears in the snapshot '
            '(or delete this sentence).',
          );
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
        } else if (forceOptionalSymbolPlaceholder) {
          buf.write(
            ' Pay special attention to $draftSymbolPlaceholder '
            '(or delete this sentence).',
          );
        }
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Proposed side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Proposed quantity: $quantity.');
        } else if (quantityPlaceholder != null) {
          buf.write(' Proposed quantity: $quantityPlaceholder.');
        }
        buf.write(
          ' Cover cash vs holdings, concentration, diversification, cash '
          'drag, and (for Practice) size vs cash and average cost. Remind '
          'me Practice is fake money. Do not emit trade JSON.',
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
        } else if (quantityPlaceholder != null) {
          buf.write(' Quantity: $quantityPlaceholder.');
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
