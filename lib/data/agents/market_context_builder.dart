import '../../core/formatting.dart';
import '../market/market_data_client.dart';
import '../market/models.dart';

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
}
