import 'package:genkit/genkit.dart';
import 'package:schemantic/schemantic.dart';

import '../../market/market_data_client.dart';
import '../../portfolio/models.dart';
import '../../settings/mandate_settings.dart';
import '../../venues/live_venue_capabilities.dart';
import '../agent_pnl_service.dart';
import '../invest_interest_proposal.dart';
import '../market_context_builder.dart';
import '../models.dart';
import '../trade_proposal.dart';

/// Callback that creates a pending Confirm-gated Invest interest proposal.
typedef ProposeInvestInterestFn = Future<String> Function({
  required List<String> add,
  required List<String> remove,
  List<String>? setSymbols,
  required String rationale,
});

/// Dependencies closed over by Genkit tools for one chat turn.
class OmniscopeAgentToolDeps {
  const OmniscopeAgentToolDeps({
    required this.marketData,
    this.practice,
    this.liveVenue,
    this.symbolHint,
    this.investInterestSymbols = const [],
    this.mandate,
    this.answerMood = AgentAnswerMood.plain,
    this.answerMoodNote,
    this.autopilotEnabled = false,
    this.proposeInvestInterest,
    this.tradeProposals = const [],
    this.chatId,
  });

  final MarketDataClient marketData;
  final PortfolioState? practice;
  final LiveVenueCapabilities? liveVenue;
  final String? symbolHint;

  /// User's Markets → Invest interest symbols for this turn.
  final List<String> investInterestSymbols;

  /// User investment policy (Settings → Mandate).
  final MandateSettings? mandate;

  /// Settings → Agents answer mood (delivery style).
  final AgentAnswerMood answerMood;

  /// Optional short style note from Settings → Agents.
  final String? answerMoodNote;

  /// Per-chat Autopilot (add-only Invest interest + trades).
  final bool autopilotEnabled;

  /// When set, [proposeInvestInterestDiff] creates a pending proposal.
  final ProposeInvestInterestFn? proposeInvestInterest;

  /// Executed/pending trade proposals for read-only P&L tools.
  final List<TradeProposal> tradeProposals;

  /// Current chat id (for chat-scoped P&L).
  final String? chatId;
}

/// Registers market / portfolio tools on [ai] for the given [deps].
class OmniscopeAgentTools {
  OmniscopeAgentTools._();

  static final _symbolInput = SchemanticType.map(
    SchemanticType.string(),
    SchemanticType.dynamicSchema(),
  );

  static List<Tool<dynamic, dynamic>> defineAll(
    Genkit ai,
    OmniscopeAgentToolDeps deps,
  ) {
    final builder = MarketContextBuilder(deps.marketData);

    final getQuotes = ai.defineTool(
      name: 'getQuotes',
      description:
          'Fetch latest quotes for one or more symbols (equities or crypto '
          'spot). Input: {"symbols":["AAPL"]} or {"symbol":"AAPL"}.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final symbols = _readSymbols(input);
        if (symbols.isEmpty) {
          return .response('No symbols provided.');
        }
        try {
          final quotes = await deps.marketData.getQuotes(symbols);
          if (quotes.isEmpty) {
            return .response('No quotes returned for ${symbols.join(", ")}.');
          }
          final lines = [
            for (final q in quotes)
              '${q.symbol}: ${q.price}'
                  '${q.currency != null ? " ${q.currency}" : ""}'
                  '${q.changePercent != null ? " (${q.changePercent!.toStringAsFixed(2)}%)" : ""}',
          ];
          return .response(lines.join('\n'));
        } catch (e) {
          return .response('Quote fetch failed: $e');
        }
      },
    );

    final getHistory = ai.defineTool(
      name: 'getHistory',
      description:
          'Fetch recent daily history for a symbol. '
          'Input: {"symbol":"AAPL","range":"1mo"} (range optional).',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final map = _asMap(input);
        final symbol = (map['symbol'] as String?)?.trim().toUpperCase() ?? '';
        if (symbol.isEmpty) {
          return .response('Provide symbol.');
        }
        final range = (map['range'] as String?)?.trim().isNotEmpty == true
            ? (map['range'] as String).trim()
            : '1mo';
        try {
          final candles = await deps.marketData.getHistory(
            symbol,
            range: range,
            interval: '1d',
          );
          if (candles.isEmpty) {
            return .response('No history for $symbol.');
          }
          final first = candles.first.close;
          final last = candles.last.close;
          final change = first == 0 ? 0.0 : ((last - first) / first) * 100;
          return .response(
            'History $symbol ($range): ${candles.length} bars; '
            'open≈$first close≈$last change≈${change.toStringAsFixed(2)}%.',
          );
        } catch (e) {
          return .response('History fetch failed: $e');
        }
      },
    );

    final getPracticePortfolio = ai.defineTool(
      name: 'getPracticePortfolio',
      description:
          'Read the user Practice (paper) cash and holdings. Optional '
          'input: {"symbol":"AAPL"} to focus a holding.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final state = deps.practice;
        if (state == null) {
          return .response('Practice portfolio is not available.');
        }
        final map = _asMap(input);
        final hint = (map['symbol'] as String?)?.trim().toUpperCase() ??
            deps.symbolHint;
        Map<String, double>? lastPrices;
        if (state.holdings.isNotEmpty) {
          try {
            final quotes = await deps.marketData.getQuotes([
              for (final h in state.holdings) h.symbol,
            ]);
            lastPrices = {for (final q in quotes) q.symbol: q.price};
          } catch (_) {}
        }
        final text = builder.buildPracticePortfolioContext(
          state: state,
          symbolHint: hint,
          listAllHoldings: true,
          lastPrices: lastPrices,
        );
        return .response(text ?? 'Practice portfolio is empty.');
      },
    );

    final getLiveBalances = ai.defineTool(
      name: 'getLiveBalances',
      description:
          'Fetch live exchange balances when credentials allow. Optional '
          'input: {"symbol":"BTC"} to focus an asset.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final client = deps.liveVenue;
        if (client == null || !client.canFetchPortfolio) {
          return .response(
            'No live exchange with portfolio credentials is available. '
            'Ask the user to connect under Settings → Data sources.',
          );
        }
        final map = _asMap(input);
        final hint = (map['symbol'] as String?)?.trim().toUpperCase() ??
            deps.symbolHint;
        final text = await builder.buildLiveExchangeContext(
          client: client,
          symbolHint: hint,
          listAllBalances: true,
        );
        return .response(
          text ?? 'Could not load live balances for ${client.displayName}.',
        );
      },
    );

    final getInvestInterest = ai.defineTool(
      name: 'getInvestInterest',
      description:
          'Read the user Invest interest list — symbols they want agents '
          'to consider for investing. No input required.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final symbols = [
          for (final s in deps.investInterestSymbols)
            if (s.trim().isNotEmpty) s.trim().toUpperCase(),
        ];
        if (symbols.isEmpty) {
          return .response(
            'Invest interest list is empty. Propose changes with '
            'proposeInvestInterestDiff (user Confirms in Activity), or the '
            'user can add symbols under Markets → Invest interest.',
          );
        }
        return .response('Invest interest: ${symbols.join(', ')}');
      },
    );

    final getMandate = ai.defineTool(
      name: 'getMandate',
      description:
          'Read the user Investment Mandate (goal, horizon, universe, '
          'max symbols, risk rails, preferred cadence). No input required. '
          'Always respect these constraints.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final mandate = deps.mandate;
        if (mandate == null) {
          return .response(
            'Mandate is not available. Assume goal=learn, '
            'universe=both, maxSymbols=20.',
          );
        }
        return .response(mandate.toAgentSummary());
      },
    );

    final getAgentPnl = ai.defineTool(
      name: 'getAgentPnl',
      description:
          'Read realized profit/loss for agent fills on a symbol. '
          'Input: {"symbol":"AAPL"} for this chat, or '
          '{"symbol":"AAPL","roleId":"intradayTrading"} for a specialty '
          'lifetime rollup. Educational only — not live brokerage P&L.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final map = _asMap(input);
        final symbols = _readSymbols(input);
        final symbol = symbols.isNotEmpty
            ? symbols.first
            : (map['symbol'] as String? ?? '').trim().toUpperCase();
        if (symbol.isEmpty) {
          return .response('Provide a symbol, e.g. {"symbol":"AAPL"}.');
        }
        final roleId = (map['roleId'] as String? ?? '').trim();
        final AgentPnlSummary summary;
        if (roleId.isNotEmpty) {
          summary = AgentPnlService.summaryForRoleSymbol(
            proposals: deps.tradeProposals,
            roleId: roleId,
            symbol: symbol,
          );
        } else {
          final chatId = deps.chatId?.trim() ?? '';
          if (chatId.isEmpty) {
            return .response(
              'No chat context. Pass roleId for a specialty rollup, '
              'e.g. {"symbol":"$symbol","roleId":"intradayTrading"}.',
            );
          }
          summary = AgentPnlService.summaryForChatSymbol(
            proposals: deps.tradeProposals,
            chatId: chatId,
            symbol: symbol,
          );
        }
        if (!summary.hasActivity) {
          return .response(
            'No executed agent fills for $symbol'
            '${roleId.isNotEmpty ? ' ($roleId)' : ' in this chat'}.',
          );
        }
        return .response(
          '${summary.toPlainLine()} '
          '(buy notional ${summary.buyNotional.toStringAsFixed(2)}, '
          'sell notional ${summary.sellNotional.toStringAsFixed(2)}, '
          '${summary.fillCount} fills). Do not invent fills beyond this.',
        );
      },
    );

    final proposeInvestInterestDiff = ai.defineTool(
      name: 'proposeInvestInterestDiff',
      description:
          'Propose a change to Markets → Invest interest. '
          'Input: {"add":["AAPL"],"remove":["MSFT"],"rationale":"why"} '
          'or {"set":["AAPL","SPY"],"rationale":"why"} for a full replace. '
          'Respect getMandate maxSymbols and universe. '
          '${deps.autopilotEnabled ? 'Autopilot is ON: add-only proposals '
              '(non-empty add, empty remove, no set) from investigation '
              'roles may apply without Confirm; remove/set still need '
              'Confirm. Prefer add-only when suggesting new symbols. ' : ''}'
          'Otherwise the user Confirms in chat / Activity — do not claim '
          'the list already changed unless Autopilot applied an add.',
      inputSchema: _symbolInput,
      fn: (input, _) async {
        final propose = deps.proposeInvestInterest;
        if (propose == null) {
          return .response(
            'Invest interest proposals are not available in this turn.',
          );
        }
        final map = _asMap(input);
        final add = _readSymbolList(map['add']);
        final remove = _readSymbolList(map['remove']);
        final setRaw = map['set'] ?? map['symbols'];
        final setSymbols = setRaw is List ? _readSymbolList(setRaw) : null;
        final rationale = (map['rationale'] as String? ?? '').trim();
        if (rationale.isEmpty) {
          return .response('Provide a short rationale.');
        }
        if (add.isEmpty && remove.isEmpty && (setSymbols == null)) {
          return .response(
            'Provide add/remove lists, or a set list to replace Invest interest.',
          );
        }
        // Soft universe hint (hard filter is educational; Confirm applies as-is
        // within maxSymbols).
        final mandate = deps.mandate;
        if (mandate != null && mandate.universe != MandateUniverse.both) {
          final candidates = [
            ...add,
            ...?setSymbols,
          ];
          for (final s in candidates) {
            final looksCrypto = s.contains('_') || s.contains('-');
            if (mandate.universe == MandateUniverse.equities && looksCrypto) {
              return .response(
                'Mandate universe is equities-only; do not propose crypto '
                'symbol $s. Adjust the list and try again.',
              );
            }
            if (mandate.universe == MandateUniverse.crypto && !looksCrypto) {
              return .response(
                'Mandate universe is crypto-only; do not propose equity '
                'symbol $s. Adjust the list and try again.',
              );
            }
          }
        }
        try {
          final draft = InvestInterestProposal.fromToolInput(
            {
              'add': add,
              'remove': remove,
              'set': ?setSymbols,
              'rationale': rationale,
            },
            roleId: 'tool',
          );
          if (!draft.isActionable) {
            return .response('Proposal has no actionable changes.');
          }
          return .response(
            await propose(
              add: add,
              remove: remove,
              setSymbols: setSymbols,
              rationale: rationale,
            ),
          );
        } catch (e) {
          return .response('Could not create proposal: $e');
        }
      },
    );

    return [
      getQuotes,
      getHistory,
      getPracticePortfolio,
      getLiveBalances,
      getInvestInterest,
      getMandate,
      getAgentPnl,
      proposeInvestInterestDiff,
    ];
  }

  static List<Tool<dynamic, dynamic>> forRole({
    required Genkit ai,
    required String roleId,
    required OmniscopeAgentToolDeps deps,
  }) {
    final all = defineAll(ai, deps);
    final byName = {for (final t in all) t.name: t};
    final names = switch (roleId) {
      'marketResearch' => const [
          'getQuotes',
          'getHistory',
          'getInvestInterest',
          'getMandate',
          'proposeInvestInterestDiff',
        ],
      'liveBalanceExplainer' => const [
          'getLiveBalances',
          'getQuotes',
          'getMandate',
        ],
      'portfolioGuide' => const [
          'getPracticePortfolio',
          'getLiveBalances',
          'getQuotes',
          'getInvestInterest',
          'getMandate',
          'getAgentPnl',
          'proposeInvestInterestDiff',
        ],
      'intradayTrading' => const [
          'getQuotes',
          'getHistory',
          'getPracticePortfolio',
          'getLiveBalances',
          'getInvestInterest',
          'getMandate',
          'getAgentPnl',
          'proposeInvestInterestDiff',
        ],
      _ => const [
          'getQuotes',
          'getHistory',
          'getInvestInterest',
          'getMandate',
        ],
    };
    return [for (final n in names) if (byName[n] != null) byName[n]!];
  }

  static Map<String, dynamic> _asMap(dynamic input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      return input.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  static List<String> _readSymbols(dynamic input) {
    final map = _asMap(input);
    final out = <String>[];
    final single = map['symbol'];
    if (single is String && single.trim().isNotEmpty) {
      out.add(single.trim().toUpperCase());
    }
    final list = map['symbols'];
    if (list is List) {
      out.addAll(_readSymbolList(list));
    }
    return out;
  }

  static List<String> _readSymbolList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item?.toString().trim().toUpperCase() ?? '';
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }
}
