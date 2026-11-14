import 'package:genkit/genkit.dart';
import 'package:schemantic/schemantic.dart';

import '../../market/market_data_client.dart';
import '../../portfolio/models.dart';
import '../../venues/live_venue_capabilities.dart';
import '../market_context_builder.dart';

/// Dependencies closed over by Genkit tools for one chat turn.
class OmniscopeAgentToolDeps {
  const OmniscopeAgentToolDeps({
    required this.marketData,
    this.practice,
    this.liveVenue,
    this.symbolHint,
  });

  final MarketDataClient marketData;
  final PortfolioState? practice;
  final LiveVenueCapabilities? liveVenue;
  final String? symbolHint;
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

    return [getQuotes, getHistory, getPracticePortfolio, getLiveBalances];
  }

  static List<Tool<dynamic, dynamic>> forRole({
    required Genkit ai,
    required String roleId,
    required OmniscopeAgentToolDeps deps,
  }) {
    final all = defineAll(ai, deps);
    final byName = {for (final t in all) t.name: t};
    final names = switch (roleId) {
      'marketResearch' => const ['getQuotes', 'getHistory'],
      'liveBalanceExplainer' => const ['getLiveBalances', 'getQuotes'],
      'portfolioGuide' => const [
          'getPracticePortfolio',
          'getLiveBalances',
          'getQuotes',
        ],
      'paperPortfolioCoach' => const ['getPracticePortfolio', 'getQuotes'],
      'intradayTrading' => const [
          'getQuotes',
          'getHistory',
          'getPracticePortfolio',
          'getLiveBalances',
        ],
      _ => const ['getQuotes', 'getHistory'],
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
      for (final item in list) {
        final s = item?.toString().trim().toUpperCase() ?? '';
        if (s.isNotEmpty) out.add(s);
      }
    }
    return out;
  }
}
