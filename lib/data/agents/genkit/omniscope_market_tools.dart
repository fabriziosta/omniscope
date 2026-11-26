import 'package:genkit/genkit.dart';

import '../agent_history_query.dart';
import 'omniscope_agent_tool_helpers.dart';
import 'omniscope_agent_tools.dart';

/// Registers quote and history tools on [ai].
List<Tool<dynamic, dynamic>> defineOmniscopeMarketTools(
  Genkit ai,
  OmniscopeAgentToolDeps deps,
) {
  final inputSchema = OmniscopeAgentToolHelpers.symbolInput;

  final getQuotes = ai.defineTool(
    name: 'getQuotes',
    description:
        'Fetch latest quotes for one or more symbols (equities or crypto '
        'spot). Returns price, day change, prev close, name, exchange, and '
        'source. Input: {"symbols":["AAPL"]} or {"symbol":"AAPL"}.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final symbols = OmniscopeAgentToolHelpers.readSymbols(input);
      if (symbols.isEmpty) {
        return .response('No symbols provided.');
      }
      try {
        final quotes = await deps.marketData.getQuotes(symbols);
        if (quotes.isEmpty) {
          return .response('No quotes returned for ${symbols.join(", ")}.');
        }
        final lines = [
          for (final q in quotes) OmniscopeAgentToolHelpers.formatQuoteLine(q),
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
        'Fetch recent price history for a symbol. '
        'Input: {"symbol":"AAPL","range":"1mo","interval":"1d"}. '
        'Allowed ranges/intervals: '
        '1d→5m|15m|1h; 5d→15m|1h; 1mo→1d; 3mo→1d; 1y→1wk|1d. '
        'Defaults to 1mo @ 1d. Returns summary + up to '
        '${AgentHistoryQuery.maxRecentBars} recent closes — not a full chart.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final symbol = (map['symbol'] as String?)?.trim().toUpperCase() ?? '';
      if (symbol.isEmpty) {
        return .response('Provide symbol.');
      }
      final pair = AgentHistoryQuery.normalize(
        range: map['range'] as String?,
        interval: map['interval'] as String?,
      );
      try {
        final candles = await deps.marketData.getHistory(
          symbol,
          range: pair.range,
          interval: pair.interval,
        );
        if (candles.isEmpty) {
          return .response('No history for $symbol.');
        }
        return .response(
          AgentHistoryQuery.formatHistory(
            symbol: symbol,
            range: pair.range,
            interval: pair.interval,
            candles: candles,
          ),
        );
      } catch (e) {
        return .response('History fetch failed: $e');
      }
    },
  );

  return [getQuotes, getHistory];
}
