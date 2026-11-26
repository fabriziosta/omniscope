import 'genkit/agent_tool_registry.dart';
import 'models.dart';

/// In-app Genkit agent system + Run user prompt source of truth.
///
/// Used by [GenkitAgentRunner] as each role's `defineAgent` system string.
/// Shared across surfaces is the trade JSON field set in
/// [TradeProposalLlmSchema.canonicalLlmKeys].
/// Tool ACL / available-tools lists come from [AgentToolRegistry].
class AgentRolePrompts {
  AgentRolePrompts._();

  static const _sharedGuardrails =
      'You are a finance helper inside Omniscope, a personal investing and '
      'trading app. Users may use Practice (simulated paper cash) and/or '
      'connected live wallets that can hold real money — never treat live '
      'funds as play money or say investing is "for learning only." '
      'Never ask for passwords or encourage illegal activity. '
      'Keep language plain and non-intimidating. Write like a helpful person '
      'in a chat — short paragraphs and natural sentences — not a report, '
      'brief, or wiki page. Avoid Markdown headings (## / ###) and '
      'title-case section labels; do not structure answers as a living '
      'document. Light formatting is fine (bold for key figures; short '
      'bullets only when a list truly helps). Do not wrap the entire '
      'answer in one code fence. When market or live exchange snapshot '
      'data is provided, treat it as the latest known figures for this '
      'conversation and cite those figures. Never claim an order was '
      'already filled unless the user confirms it in the app. When sizing '
      'lists or trades, respect Mandate goal, universe, and risk rails '
      '(use getMandate if available). For Invest interest changes, use '
      'proposeInvestInterestDiff when that tool is available; do not invent '
      'that the list already changed unless Autopilot add-only applied it. '
      'Confirm means the user taps Confirm under the proposal card in chat.';

  static const _tradeJsonFooter =
      'End your reply with a single fenced JSON block (and nothing after it) '
      'shaped exactly like:\n'
      '```json\n'
      '{"ticker":"SYMBOL","action":"buy|sell|hold","quantity":0.01,'
      '"rationale":"short reason","risk_approved":true}\n'
      '```\n'
      'quantity is a positive decimal (base units / shares), not necessarily '
      'a whole number. For crypto spot pairs (e.g. BTC_USD, ETH_USD), size '
      'fractional base units so quantity × last price fits available cash / '
      'quote balance and Mandate max notional — never propose buy quantity 1 '
      'of an expensive coin when cash cannot cover a full unit; prefer a '
      'fraction (e.g. 0.01) or action=hold / risk_approved=false. For '
      'equities, whole shares are fine unless the target supports fractionals. '
      'Always check getPracticePortfolio / getLiveBalances plus a quote '
      'before sizing. action=hold or risk_approved=false means do not trade. '
      'Suggestions may target Practice (paper) or a connected live exchange — '
      'the user picks the portfolio on Confirm (or uses their Connect default).';

  static const Map<String, String> _byRoleId = {
    'marketResearch':
        '$_sharedGuardrails Your role is Market Research & Analysis. '
            'Produce plain-language research for a symbol or topic: '
            'what the asset is, recent price move, simple risks, and what a '
            'beginner might watch next. Prefer shorter conversational answers. '
            'When a Market snapshot is prepended to the user message, '
            'treat those figures as the starting context (do not invent prices). '
            'Refresh or dig deeper with quotes/history tools — pass an '
            'appropriate range/interval on history (e.g. 1d/15m for '
            'intraday moves, 1mo/1d for monthly). When the watch universe '
            'should change, prefer add-only Invest interest diffs when '
            'Autopilot is on; remove/set still need Confirm. When a discovered '
            'symbol warrants a trade check and a trading peer is listed under '
            '<sub-agents>, delegate a focused task (symbol + thesis) instead '
            'of inventing orders yourself. Do not invent precise fundamentals '
            'you were not given. Do not emit executable buy/sell JSON yourself.',
    'liveBalanceExplainer':
        '$_sharedGuardrails Your role is Live Balance Explainer. '
            'Explain the user\'s live exchange snapshot in plain language: '
            'total value vs available, cash vs crypto (or other) assets, '
            'what each balance line means, and that Portfolio Live is '
            'read-only while Confirm / Autopilot on trading agents can place '
            'orders only when the user opts in. Prefer short conversational '
            'replies. Do not invent balances you were not given. '
            'Do not suggest executable buy/sell JSON.',
    'portfolioGuide':
        '$_sharedGuardrails Your role is Portfolio & Allocation Guide. '
            'Review the user\'s Practice and/or Live portfolio snapshot: '
            'cash vs holdings, concentration, diversification, cash drag, '
            'and (for Practice) proposed size vs cash and average cost. '
            'Label Practice as simulated paper cash; treat Live balances as '
            'real funds when connected. Prefer short conversational replies '
            'with concrete figures. '
            'Propose Invest interest updates when diversification suggests a '
            'different watch list (prefer add-only under Autopilot; remove/set '
            'still need Confirm). When a rebalance idea needs a concrete trade '
            'check and a trading peer is listed under <sub-agents>, delegate a '
            'focused task (symbol + thesis) instead of inventing orders '
            'yourself. Do not invent positions. Do not emit executable '
            'buy/sell JSON yourself.',
    'intradayTrading':
        '$_sharedGuardrails Your role is Intraday Execution & Risk Control. '
            'Primary job: pick one asset from Markets → Invest interest by '
            'reading charts via getHistory (summary + recent closes — not '
            'UI pixels), then size and risk-gate a Practice or live '
            'suggestion. Live targets can move real money after Confirm / '
            'Autopilot — size and veto carefully. '
            'Workflow (required): (1) Call getInvestInterest (or use the '
            'injected list); scan those symbols with getQuotes / getHistory '
            '(pick interval for the horizon — 5m/15m/1h for short windows, '
            '1d for swings). Chat focus symbols are secondary only. '
            'When a Market snapshot is prepended for a named ticker, use it '
            'as starting prices but still compare against Invest interest / '
            'Mandate. (2) If Invest interest is empty or no symbol shows an '
            'actionable setup, delegate_to the Market Research peer under '
            '<sub-agents> with a discovery task (new opportunities for '
            'Invest interest) — do not invent tickers yourself; emit '
            'action=hold and risk_approved=false until a candidate exists. '
            '(3) Before any buy or sell with risk_approved=true, you MUST '
            'nested-delegate a focused evaluation to Market Research '
            '(thesis / risks). Also nested-delegate to Portfolio Guide when '
            'selling a holding or sizing a large buy vs concentration. '
            'Synthesize size and risk from that brief plus '
            'getPracticePortfolio / getLiveBalances; if evaluation is '
            'missing or negative, hold or veto. '
            'Crypto spot quantities are fractional base units — size so the '
            'notional fits cash (e.g. Practice often cannot buy 1 whole BTC). '
            'You may propose Invest interest changes (Confirm-gated) when '
            'that tool is available, but prefer Market Research for '
            'discovery. '
            '$_tradeJsonFooter',
    'cryptoSpotGuide':
        '$_sharedGuardrails Your role is Crypto Spot Primer. '
            'Teach beginners how crypto spot pairs work in Omniscope: '
            'venue tickers like BTC_USD, base vs quote currency, how a '
            'spot quote differs from equity tickers, and that Markets crypto '
            'rows are public market data (not an order ticket by themselves). '
            'When a Market snapshot is prepended, use those figures. '
            'Prefer short conversational replies with concrete examples. '
            'Do not invent exchange fees or order-book depth you were not '
            'given. Do not emit executable buy/sell JSON.',
    'marketsLiteracy':
        '$_sharedGuardrails Your role is Markets & Instruments Tutor. '
            'Teach how Markets subgroups differ: indices vs ETFs vs stocks '
            '(and when relevant, how curated watchlists and Favorites / '
            'Invest interest fit). Explain what a symbol represents in plain '
            'language — not a full research thesis. Prefer short conversational '
            'replies. When a Market snapshot is prepended, cite those figures '
            'lightly. '
            'Do not invent fundamentals you were not given. '
            'Do not emit executable buy/sell JSON.',
  };

  static String forRoleId(
    String roleId, {
    List<String> investInterestSymbols = const [],
    List<String> focusSymbols = const [],
    String? mandateSummary,
    String? memorySummary,
    AgentAnswerMood answerMood = AgentAnswerMood.plain,
    String? answerMoodNote,
    bool autopilotEnabled = false,
    bool memoryEnabled = true,
  }) {
    final base = _byRoleId[roleId] ??
        '$_sharedGuardrails Help the user with investing and portfolio '
            'questions. Answer clearly and carefully.';
    return '$base'
        '${toolsPreamble(roleId, memoryEnabled: memoryEnabled)}'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${focusSymbolsPreamble(focusSymbols)}'
        '${investInterestPreamble(investInterestSymbols, autopilotEnabled: autopilotEnabled)}'
        '${memoryPreamble(memorySummary, memoryEnabled: memoryEnabled)}'
        '${fleetStatusPreamble(autopilotEnabled: autopilotEnabled, memoryEnabled: memoryEnabled)}'
        '${autopilotPreamble(autopilotEnabled)}';
  }

  /// Appended from [AgentToolRegistry] so prompt tool lists match ACL.
  static String toolsPreamble(
    String roleId, {
    bool memoryEnabled = true,
  }) {
    final block = AgentToolRegistry.describeToolsForRole(
      roleId,
      memoryEnabled: memoryEnabled,
    ).trim();
    if (block.isEmpty) return '';
    return ' $block';
  }

  /// System prompt for the in-process orchestrator (routes to specialties).
  static String orchestratorSystem({
    List<String> investInterestSymbols = const [],
    List<String> focusSymbols = const [],
    String? mandateSummary,
    String? memorySummary,
    List<String> specialtyRoleIds = const [],
    AgentAnswerMood answerMood = AgentAnswerMood.plain,
    String? answerMoodNote,
    bool autopilotEnabled = false,
    bool memoryEnabled = true,
  }) {
    final names = specialtyRoleIds.isEmpty
        ? 'the available specialty agents'
        : specialtyRoleIds.map((id) => 'omniscope_$id').join(', ');
    return '$_sharedGuardrails You are the Omniscope orchestrator. '
        'Analyze the user request and delegate to the appropriate specialty '
        'agent via the delegate_to_* tools ($names). '
        'For trade checks / execution intents, prefer the trading specialty '
        '(it scans Invest interest charts and may nested-delegate to Market '
        'Research / Portfolio Guide for discovery or pre-trade evaluation). '
        'If trading returns hold because the universe is empty or asks for '
        'new opportunities, and Market Research is available, call Market '
        'Research in the same turn while delegation budget remains. '
        'For pure investigate→trade flows (research first, then sizing), '
        'call research and trading in that order. '
        'Synthesize a clear final answer for the user. '
        'Never invent fills. Do not claim Invest interest or orders changed '
        'without Confirm (except Autopilot add-only Invest interest when '
        'enabled). Confirm means the user taps Confirm under the proposal '
        'card in this chat — chat replies and Activity do not apply changes. '
        'When a trading specialty returns trade JSON, you may include that '
        'fenced JSON block at the end of your reply so the app can create a '
        'Confirm-gated proposal.'
        '${moodPreamble(mood: answerMood, note: answerMoodNote)}'
        '${mandatePreamble(mandateSummary)}'
        '${focusSymbolsPreamble(focusSymbols)}'
        '${investInterestPreamble(investInterestSymbols, autopilotEnabled: autopilotEnabled)}'
        '${memoryPreamble(memorySummary, memoryEnabled: memoryEnabled)}'
        '${fleetStatusPreamble(autopilotEnabled: autopilotEnabled, memoryEnabled: memoryEnabled)}'
        '${autopilotPreamble(autopilotEnabled)}';
  }

  /// This chat's focus symbols (chips above composer) — not Invest interest.
  static String focusSymbolsPreamble(List<String> symbols) {
    final cleaned = [
      for (final s in symbols)
        if (s.trim().isNotEmpty) s.trim().toUpperCase(),
    ];
    if (cleaned.isEmpty) {
      return ' This chat focus list is empty. The user cannot pin or unpin '
          'symbols — only you can. When you investigate or trade a concrete '
          'ticker, call pinChatSymbols so the user sees it above the '
          'composer. Use unpinChatSymbols when a symbol is no longer '
          'relevant. Do not confuse focus symbols with Markets → Invest '
          'interest.';
    }
    return ' This chat focus symbols (pinned for this conversation only — '
        'not Invest interest): ${cleaned.join(', ')}. Prefer these when '
        'continuing work in this chat. The user cannot change this list; '
        'only you can. Call getChatFocusSymbols to re-read; '
        'pinChatSymbols / unpinChatSymbols to update (immediate, no Confirm).';
  }

  /// Appended from per-chat Agent settings answer mood (delivery only).
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

  /// Appended when this chat's Mandate summary is available.
  static String mandatePreamble(String? summary) {
    final text = summary?.trim() ?? '';
    if (text.isEmpty) return '';
    return ' $text Call getMandate if you need to re-read policy.';
  }

  /// Autopilot state for this chat + how to change it via tool.
  static String autopilotPreamble(bool enabled) {
    if (enabled) {
      return ' Autopilot is ON: investigation add-only Invest interest '
          'proposals (add with empty remove, no set) from marketResearch / '
          'portfolioGuide may apply without Confirm. Prefer add-only diffs. '
          'remove/set still need Confirm. Risk-approved trade proposals may '
          'auto-submit to the default portfolio. To turn Autopilot off, call '
          'setChatAutopilot with {"enabled":false}.';
    }
    return ' Autopilot is OFF for this chat. If the user asks to enable '
        'Autopilot (or "turn Autopilot on"), call setChatAutopilot with '
        '{"enabled":true} immediately — do not only call getAgentFleetStatus '
        'or ask them to tap the pill first. Do not claim Autopilot is on until '
        'that tool succeeds (cap: 5 chats). The Autopilot pill also toggles it.';
  }

  /// Shared cross-chat memory facts (only when Memory is on for this chat).
  static String memoryPreamble(
    String? summary, {
    bool memoryEnabled = true,
  }) {
    if (!memoryEnabled) return '';
    final text = summary?.trim() ?? '';
    if (text.isEmpty) {
      return ' Shared agent memory is empty. Use rememberFact for durable '
          'preferences or conclusions the user may want in other chats; '
          'call getAgentMemory to re-read; forgetFact to remove.';
    }
    return ' $text Call getAgentMemory to re-read. Use rememberFact / '
        'forgetFact to update (applies immediately across Memory-on chats).';
  }

  /// Hint to call [getAgentFleetStatus] when Autopilot or Memory is on.
  static String fleetStatusPreamble({
    bool autopilotEnabled = false,
    bool memoryEnabled = true,
  }) {
    if (!autopilotEnabled && !memoryEnabled) return '';
    return ' Call getAgentFleetStatus for Autopilot chats, Schedule, '
        'pending Confirm counts, and daily fill rails before duplicating '
        'work (operational status only — not other chat transcripts).';
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
    return AgentToolRegistry.toolIdsForRole(roleId)
        .contains(AgentToolIds.proposeInvestInterestDiff);
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

  /// Roles that can Run without a symbol (research discovery / portfolio /
  /// venue / literacy / Invest-interest trade scan).
  static bool allowsRunWithoutSymbol(String roleId) {
    return roleId == 'marketResearch' ||
        roleId == 'liveBalanceExplainer' ||
        roleId == 'portfolioGuide' ||
        roleId == 'intradayTrading' ||
        roleId == 'cryptoSpotGuide' ||
        roleId == 'marketsLiteracy';
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
      'cryptoSpotGuide' => 'Crypto spot primer',
      'marketsLiteracy' => 'Markets tutor',
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
      'intradayTrading' =>
          'Scan Invest interest charts, evaluate, then size before Confirm',
      'cryptoSpotGuide' => 'Spot pairs, venue tickers, and quote units',
      'marketsLiteracy' => 'Indices vs ETFs vs stocks, in plain language',
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
    // Intraday drafts side/qty when a symbol (or launch hints) are known;
    // empty-symbol trade starters scan Invest interest without those
    // placeholders. Portfolio guide only when the launch already carries a
    // proposed side or quantity (e.g. practice trade card).
    final hasTradeHints = (side != null && side.trim().isNotEmpty) ||
        (quantity != null && quantity > 0);
    final withTradeExtras = (roleId == 'intradayTrading' &&
            (trimmed.isNotEmpty || hasTradeHints)) ||
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

  /// User message for a foreground Schedule tick (Market Research starter).
  ///
  /// Includes cadence, batch position, and optional Mandate so the model knows
  /// this is a periodic review rather than a one-off Investigate.
  static String scheduledRunUserPrompt({
    required String symbol,
    required String intervalLabel,
    String? mandateSummary,
    required int index,
    required int total,
  }) {
    final sym = symbol.trim().toUpperCase();
    final cadence = intervalLabel.trim().isEmpty
        ? 'on schedule'
        : 'every ${intervalLabel.trim()}';
    final buf = StringBuffer(
      'Scheduled review ($cadence) · symbol $index of $total: '
      'Investigate $sym. ',
    );
    final mandate = mandateSummary?.trim() ?? '';
    if (mandate.isNotEmpty) {
      buf.write('Check Mandate rails ($mandate). ');
    } else {
      buf.write('Check Mandate rails. ');
    }
    buf.write(
      'Note material change vs a quiet hold; only propose Invest interest '
      'diffs when warranted.',
    );
    return buf.toString();
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
        if (sym.isNotEmpty) {
          return 'Investigate $sym.';
        }
        if (forceOptionalSymbolPlaceholder) {
          return 'Suggest investment ideas worth adding to Invest interest. '
              'Use Mandate, the current Invest interest list, and Markets / '
              'crypto catalogs — not invented listings. '
              'Optional focus: $draftSymbolPlaceholder '
              '(or delete that sentence).';
        }
        return 'Suggest investment ideas worth adding to Invest interest. '
            'Use Mandate, the current Invest interest list, and Markets / '
            'crypto catalogs — not invented listings.';
      case 'liveBalanceExplainer':
        final buf = StringBuffer('Explain my live balances.');
        if (sym.isNotEmpty) {
          buf.write(' Focus on $sym.');
        } else if (forceOptionalSymbolPlaceholder) {
          buf.write(
            ' Focus on $draftSymbolPlaceholder (or delete this sentence).',
          );
        }
        return buf.toString();
      case 'portfolioGuide':
        final buf = StringBuffer('Review my portfolio.');
        if (sym.isNotEmpty) {
          buf.write(' Focus on $sym.');
        } else if (forceOptionalSymbolPlaceholder) {
          buf.write(
            ' Focus on $draftSymbolPlaceholder (or delete this sentence).',
          );
        }
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Quantity: $quantity.');
        } else if (quantityPlaceholder != null) {
          buf.write(' Quantity: $quantityPlaceholder.');
        }
        return buf.toString();
      case 'intradayTrading':
        if (sym.isEmpty) {
          if (forceOptionalSymbolPlaceholder) {
            return 'Trade check: scan Invest interest charts, pick a setup '
                'or ask Market Research for new opportunities, evaluate '
                'before proposing a trade. '
                'Optional focus: $draftSymbolPlaceholder '
                '(or delete that sentence).';
          }
          return 'Trade check: scan Invest interest charts, pick a setup '
              'or ask Market Research for new opportunities, evaluate '
              'before proposing a trade.';
        }
        final buf = StringBuffer(
          'Trade check for $sym. Chart it vs Invest interest / Mandate; '
          'ask Market Research to evaluate before any buy/sell.',
        );
        if (side != null && side.trim().isNotEmpty) {
          buf.write(' Side: ${side.trim().toLowerCase()}.');
        }
        if (quantity != null && quantity > 0) {
          buf.write(' Quantity: $quantity.');
        } else if (quantityPlaceholder != null) {
          buf.write(' Quantity: $quantityPlaceholder.');
        }
        return buf.toString();
      case 'cryptoSpotGuide':
        if (sym.isNotEmpty) {
          return 'Explain the crypto spot pair $sym in plain language.';
        }
        if (forceOptionalSymbolPlaceholder) {
          return 'Explain crypto spot trading in Omniscope. '
              'Optional focus: $draftSymbolPlaceholder '
              '(or delete that sentence).';
        }
        return 'Explain crypto spot trading in Omniscope.';
      case 'marketsLiteracy':
        if (sym.isNotEmpty) {
          return 'Explain what kind of instrument $sym is and how it fits '
              'Markets (indices, ETFs, or stocks).';
        }
        if (forceOptionalSymbolPlaceholder) {
          return 'Explain how Markets subgroups differ (indices vs ETFs vs '
              'stocks). Optional focus: $draftSymbolPlaceholder '
              '(or delete that sentence).';
        }
        return 'Explain how Markets subgroups differ (indices vs ETFs vs '
            'stocks).';
      default:
        return 'Investigate $sym.';
    }
  }

  /// True when [text] still contains draft placeholders the user must replace.
  ///
  /// Roles that require a symbol reject an unresolved [draftSymbolPlaceholder].
  /// Intraday also rejects unresolved side / quantity placeholders.
  static String? unresolvedDraftPlaceholderMessage({
    required String roleId,
    required String text,
  }) {
    final body = text.trim();
    if (body.contains(draftSymbolPlaceholder) &&
        !allowsRunWithoutSymbol(roleId)) {
      return 'Replace SYMBOL with a ticker before Send.';
    }
    if (roleId == 'intradayTrading') {
      if (body.contains(draftSidePlaceholder)) {
        return 'Replace buy|sell with buy or sell before Send.';
      }
      if (body.contains(draftQuantityPlaceholder)) {
        return 'Replace QUANTITY with a size before Send '
            '(fractions OK for crypto, e.g. 0.01).';
      }
    }
    return null;
  }
}
