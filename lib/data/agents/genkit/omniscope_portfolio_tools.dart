import 'package:genkit/genkit.dart';

import '../agent_pnl_service.dart';
import '../market_context_builder.dart';
import 'omniscope_agent_tool_helpers.dart';
import 'omniscope_agent_tools.dart';

/// Registers practice, live, mandate, invest-interest read, and P&L tools.
List<Tool<dynamic, dynamic>> defineOmniscopePortfolioTools(
  Genkit ai,
  OmniscopeAgentToolDeps deps,
) {
  final builder = MarketContextBuilder(deps.marketData);
  final inputSchema = OmniscopeAgentToolHelpers.symbolInput;

  final getPracticePortfolio = ai.defineTool(
    name: 'getPracticePortfolio',
    description:
        'Read the user Practice (paper) cash and holdings. Optional '
        'input: {"symbol":"AAPL"} to focus a holding.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final state = deps.practice;
      if (state == null) {
        return .response('Practice portfolio is not available.');
      }
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final hint = (map['symbol'] as String?)?.trim().toUpperCase() ??
          deps.symbolHint;
      Map<String, double>? lastPrices;
      final quoteSymbols = <String>{
        for (final h in state.holdings) h.symbol,
        if (hint != null && hint.trim().isNotEmpty) hint.trim().toUpperCase(),
      };
      if (quoteSymbols.isNotEmpty) {
        try {
          final quotes =
              await deps.marketData.getQuotes(quoteSymbols.toList());
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
    inputSchema: inputSchema,
    fn: (input, _) async {
      final client = deps.liveVenue;
      if (client == null || !client.canFetchPortfolio) {
        return .response(
          'No live exchange with portfolio credentials is available. '
          'Ask the user to connect under Settings → Data sources.',
        );
      }
      final map = OmniscopeAgentToolHelpers.asMap(input);
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
    inputSchema: inputSchema,
    fn: (input, _) async {
      final symbols = [
        for (final s in deps.investInterestSymbols)
          if (s.trim().isNotEmpty) s.trim().toUpperCase(),
      ];
      if (symbols.isEmpty) {
        return .response(
          'Invest interest list is empty. Propose changes with '
          'proposeInvestInterestDiff (user taps Confirm under the '
          'proposal card in chat), or the user can add symbols under '
          'Markets → Invest interest.',
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
    inputSchema: inputSchema,
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
        'lifetime rollup. In-app agent fill P&L — not a substitute for '
        'the venue\'s official brokerage statement.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final symbols = OmniscopeAgentToolHelpers.readSymbols(input);
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

  return [
    getPracticePortfolio,
    getLiveBalances,
    getInvestInterest,
    getMandate,
    getAgentPnl,
  ];
}
