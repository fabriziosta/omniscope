import '../../core/formatting.dart';
import '../crypto/crypto_exchange_client.dart';
import '../crypto/exchange_portfolio.dart';
import '../market/market_data_client.dart';
import '../market/models.dart';
import '../portfolio/models.dart';
import '../portfolio/portfolio_catalog.dart';

/// Builds a compact market snapshot string for LLM context.
class MarketContextBuilder {
  MarketContextBuilder(this._client);

  final MarketDataClient _client;

  /// Prefer an explicit symbol; otherwise try to extract a ticker-like token
  /// that the user typed in uppercase (e.g. `AAPL`, `BTC_USD`).
  static String? extractSymbolHint(String text) {
    final match =
        RegExp(r'\b([A-Z]{1,5}(?:[._-][A-Z0-9]{1,10})?)\b').firstMatch(text);
    final raw = match?.group(1);
    if (raw == null) return null;
    const stop = {
      'I',
      'A',
      'THE',
      'AND',
      'OR',
      'FOR',
      'TO',
      'OF',
      'ON',
      'IN',
      'IS',
      'IT',
      'MY',
      'ME',
      'WE',
      'US',
      'RUN',
      'BUY',
      'SELL',
      'ETF',
      'CEO',
      'IPO',
    };
    if (stop.contains(raw)) return null;
    return raw;
  }

  Future<String?> buildForSymbol(String symbol) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return null;

    Quote? quote;
    List<Candle> history = const [];
    try {
      final quotes = await _client.getQuotes([sym]);
      if (quotes.isNotEmpty) quote = quotes.first;
    } catch (_) {
      // Still try history; may fail too.
    }
    try {
      history = await _client.getHistory(
        sym,
        range: '1mo',
        interval: '1d',
      );
    } catch (_) {
      // Optional enrichment.
    }

    if (quote == null && history.isEmpty) return null;

    final buf = StringBuffer('Market snapshot for $sym (educational):\n');
    if (quote != null) {
      buf.writeln(
        '- Last: ${formatMoney(quote.price)}'
        '${quote.currency != null ? ' ${quote.currency}' : ''}',
      );
      if (quote.changePercent != null) {
        buf.writeln('- Day change: ${formatPercent(quote.changePercent)}');
      }
      if (quote.previousClose != null) {
        buf.writeln('- Prev close: ${formatMoney(quote.previousClose)}');
      }
      if (quote.name != null && quote.name!.isNotEmpty) {
        buf.writeln('- Name: ${quote.name}');
      }
      if (quote.exchange != null && quote.exchange!.isNotEmpty) {
        buf.writeln('- Exchange: ${quote.exchange}');
      }
      if (quote.dataSource != null && quote.dataSource!.isNotEmpty) {
        buf.writeln('- Source: ${quote.dataSource}');
      }
    }

    if (history.length >= 2) {
      final first = history.first.close;
      final last = history.last.close;
      final pct = first == 0 ? null : (last - first) / first;
      buf.writeln(
        '- ~1M range closes: ${formatMoney(first)} → ${formatMoney(last)}'
        '${pct != null ? ' (${formatPercent(pct)})' : ''}',
      );
      double? hi;
      double? lo;
      for (final c in history) {
        final h = c.high ?? c.close;
        final l = c.low ?? c.close;
        hi = hi == null ? h : (h > hi ? h : hi);
        lo = lo == null ? l : (l < lo ? l : lo);
      }
      if (hi != null && lo != null) {
        buf.writeln(
          '- ~1M high/low: ${formatMoney(hi)} / ${formatMoney(lo)}',
        );
      }
    }

    return buf.toString().trimRight();
  }

  /// Practice paper cash / holdings for coaching / allocation / trading.
  ///
  /// When [listAllHoldings] is true, list the full book (up to 24) and optionally
  /// include mark-to-market weights from [lastPrices].
  String? buildPracticePortfolioContext({
    required PortfolioState state,
    String? symbolHint,
    bool listAllHoldings = false,
    Map<String, double>? lastPrices,
  }) {
    final buf = StringBuffer(
      'Practice portfolio context '
      '(id=${PortfolioDescriptor.practiceId}; educational — user must Confirm '
      'in app; fake money only):\n',
    );
    buf.writeln('- Cash: ${formatMoney(state.cash)}');
    final hint = symbolHint?.trim().toUpperCase();
    if (listAllHoldings && hint != null && hint.isNotEmpty) {
      buf.writeln('- Focus symbol hint: $hint');
    }

    double holdingsValue = 0;
    if (lastPrices != null && lastPrices.isNotEmpty) {
      for (final h in state.holdings) {
        final px = lastPrices[h.symbol] ?? h.avgCost;
        holdingsValue += h.shares * px;
      }
      final total = state.cash + holdingsValue;
      buf.writeln('- Holdings value (approx): ${formatMoney(holdingsValue)}');
      buf.writeln('- Total value (approx): ${formatMoney(total)}');
      if (total > 0) {
        buf.writeln(
          '- Cash weight (approx): ${formatPercent(state.cash / total)}',
        );
      }
    }

    final limit = listAllHoldings ? 24 : 12;
    var listed = 0;
    for (final h in state.holdings) {
      if (listed >= limit) break;
      if (!listAllHoldings &&
          hint != null &&
          hint.isNotEmpty &&
          h.symbol != hint &&
          !hint.startsWith('${h.symbol}_')) {
        continue;
      }
      final px = lastPrices?[h.symbol];
      final value = px == null ? null : h.shares * px;
      final weight = (value != null && holdingsValue + state.cash > 0)
          ? value / (holdingsValue + state.cash)
          : null;
      buf.writeln(
        '- ${h.symbol}: qty ${h.shares}, avg cost ${formatMoney(h.avgCost)}'
        '${value != null ? ', value ${formatMoney(value)}' : ''}'
        '${weight != null ? ' (${formatPercent(weight)})' : ''}',
      );
      listed++;
    }
    if (listed == 0 && state.holdings.isNotEmpty) {
      for (final h in state.holdings.take(8)) {
        buf.writeln(
          '- ${h.symbol}: qty ${h.shares}, avg cost ${formatMoney(h.avgCost)}',
        );
      }
    } else if (state.holdings.isEmpty) {
      buf.writeln('- Holdings: none');
    }
    return buf.toString().trimRight();
  }

  /// Append live exchange balances for trading / balance-explainer roles.
  ///
  /// When [listAllBalances] is true (Live Balance Explainer), list more assets
  /// and only prefer [symbolHint] without dropping the rest of the book.
  Future<String?> buildLiveExchangeContext({
    required CryptoExchangeClient client,
    String? symbolHint,
    bool listAllBalances = false,
  }) async {
    if (!client.canFetchPortfolio) return null;
    ExchangePortfolioSnapshot snapshot;
    try {
      snapshot = await client.fetchPortfolio();
    } catch (_) {
      return null;
    }

    final buf = StringBuffer(
      'Live exchange context for ${snapshot.exchangeName} '
      '(id=${snapshot.exchangeId}; educational — Portfolio Live is read-only; '
      'user must Confirm in app before any order):\n',
    );
    if (snapshot.totalValue != null) {
      buf.writeln(
        '- Total value: ${formatMoney(snapshot.totalValue)}'
        '${snapshot.currency.isNotEmpty ? ' ${snapshot.currency}' : ''}',
      );
    }
    if (snapshot.availableValue != null) {
      buf.writeln(
        '- Available: ${formatMoney(snapshot.availableValue)}'
        '${snapshot.currency.isNotEmpty ? ' ${snapshot.currency}' : ''}',
      );
    }
    final hint = symbolHint?.trim().toUpperCase();
    final base = hint != null && hint.contains('_')
        ? hint.split('_').first
        : hint;
    final limit = listAllBalances ? 24 : 12;
    var listed = 0;

    if (listAllBalances) {
      if (base != null && base.isNotEmpty) {
        buf.writeln('- Focus asset hint: $base');
      }
      for (final bal in snapshot.balances) {
        if (listed >= limit) break;
        buf.writeln(
          '- ${bal.asset}: qty ${bal.quantity}'
          '${bal.available != null ? ' (avail ${bal.available})' : ''}'
          '${bal.marketValue != null ? ', value ${formatMoney(bal.marketValue)}' : ''}',
        );
        listed++;
      }
      if (listed == 0) {
        buf.writeln('- Holdings: none (or all zero)');
      }
      return buf.toString().trimRight();
    }

    for (final bal in snapshot.balances) {
      if (listed >= limit) break;
      if (base != null &&
          base.isNotEmpty &&
          bal.asset.toUpperCase() != base &&
          bal.asset.toUpperCase() != snapshot.currency.toUpperCase()) {
        continue;
      }
      buf.writeln(
        '- ${bal.asset}: qty ${bal.quantity}'
        '${bal.available != null ? ' (avail ${bal.available})' : ''}'
        '${bal.marketValue != null ? ', value ${formatMoney(bal.marketValue)}' : ''}',
      );
      listed++;
    }
    if (listed == 0) {
      for (final bal in snapshot.balances.take(8)) {
        buf.writeln(
          '- ${bal.asset}: qty ${bal.quantity}'
          '${bal.marketValue != null ? ', value ${formatMoney(bal.marketValue)}' : ''}',
        );
      }
    }
    return buf.toString().trimRight();
  }

  /// Combine market snapshot + Practice and/or live venue balances.
  Future<String?> buildForTradingSymbol({
    required String symbol,
    CryptoExchangeClient? exchangeClient,
    PortfolioState? practiceState,
  }) async {
    final market = await buildForSymbol(symbol);
    String? portfolioCtx;
    if (practiceState != null) {
      portfolioCtx = buildPracticePortfolioContext(
        state: practiceState,
        symbolHint: symbol,
      );
    } else if (exchangeClient != null) {
      portfolioCtx = await buildLiveExchangeContext(
        client: exchangeClient,
        symbolHint: symbol,
      );
    }
    if (market == null && portfolioCtx == null) return null;
    if (market == null) return portfolioCtx;
    if (portfolioCtx == null) return market;
    return '$market\n\n$portfolioCtx';
  }
}
