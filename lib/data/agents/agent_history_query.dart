import '../market/models.dart';

/// Whitelisted range/interval pairs and compact history formatting for agents.
abstract final class AgentHistoryQuery {
  /// Max recent close lines included in tool output.
  static const maxRecentBars = 15;

  /// Safe Yahoo / crypto chart pairs (range → allowed intervals).
  static const allowedIntervalsByRange = <String, Set<String>>{
    '1d': {'5m', '15m', '1h'},
    '5d': {'15m', '1h'},
    '1mo': {'1d'},
    '3mo': {'1d'},
    '1y': {'1wk', '1d'},
  };

  /// Default interval when the model only provides a range.
  static const defaultIntervalByRange = <String, String>{
    '1d': '15m',
    '5d': '1h',
    '1mo': '1d',
    '3mo': '1d',
    '1y': '1wk',
  };

  /// Normalize to a whitelist pair; unknown input falls back to `1mo`/`1d`.
  static ({String range, String interval}) normalize({
    String? range,
    String? interval,
  }) {
    final rawRange = range?.trim() ?? '';
    final r = allowedIntervalsByRange.containsKey(rawRange) ? rawRange : '1mo';
    final allowed = allowedIntervalsByRange[r]!;
    final rawInterval = interval?.trim() ?? '';
    if (rawInterval.isNotEmpty && allowed.contains(rawInterval)) {
      return (range: r, interval: rawInterval);
    }
    return (
      range: r,
      interval: defaultIntervalByRange[r] ?? allowed.first,
    );
  }

  /// Human-readable summary + capped recent closes for the LLM.
  static String formatHistory({
    required String symbol,
    required String range,
    required String interval,
    required List<Candle> candles,
  }) {
    if (candles.isEmpty) {
      return 'No history for $symbol.';
    }
    final first = candles.first.close;
    final last = candles.last.close;
    final changePct = first == 0 ? 0.0 : ((last - first) / first) * 100;
    double? hi;
    double? lo;
    for (final c in candles) {
      final h = c.high ?? c.close;
      final l = c.low ?? c.close;
      hi = hi == null ? h : (h > hi ? h : hi);
      lo = lo == null ? l : (l < lo ? l : lo);
    }

    final buf = StringBuffer(
      'History $symbol ($range @ $interval): ${candles.length} bars; '
      'open≈${_num(first)} close≈${_num(last)} '
      'change≈${changePct.toStringAsFixed(2)}%',
    );
    if (hi != null && lo != null) {
      buf.write('; high≈${_num(hi)} low≈${_num(lo)}');
    }
    buf.writeln('.');

    final recent = candles.length <= maxRecentBars
        ? candles
        : candles.sublist(candles.length - maxRecentBars);
    buf.writeln('Recent closes (oldest→newest):');
    for (final c in recent) {
      buf.writeln('${_barLabel(c.time, interval)} ${_num(c.close)}');
    }
    return buf.toString().trimRight();
  }

  static String _num(double v) {
    if (v == v.roundToDouble() && v.abs() >= 1) {
      return v.toStringAsFixed(2);
    }
    if (v.abs() >= 100) return v.toStringAsFixed(2);
    if (v.abs() >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }

  static String _barLabel(DateTime time, String interval) {
    final utc = time.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final intraday = interval.endsWith('m') || interval.endsWith('h');
    if (!intraday) return '$y-$m-$d';
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    return '$y-$m-$d ${hh}:$mm UTC';
  }
}
