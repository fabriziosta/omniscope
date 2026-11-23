import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_history_query.dart';
import 'package:omniscope/data/market/models.dart';

void main() {
  group('AgentHistoryQuery.normalize', () {
    test('defaults to 1mo / 1d', () {
      final pair = AgentHistoryQuery.normalize();
      expect(pair.range, '1mo');
      expect(pair.interval, '1d');
    });

    test('keeps whitelisted interval for range', () {
      final pair = AgentHistoryQuery.normalize(range: '1d', interval: '5m');
      expect(pair.range, '1d');
      expect(pair.interval, '5m');
    });

    test('rejects invalid interval and uses range default', () {
      final pair = AgentHistoryQuery.normalize(range: '1d', interval: '1d');
      expect(pair.range, '1d');
      expect(pair.interval, '15m');
    });

    test('unknown range falls back to 1mo/1d', () {
      final pair = AgentHistoryQuery.normalize(range: '2y', interval: '1d');
      expect(pair.range, '1mo');
      expect(pair.interval, '1d');
    });
  });

  group('AgentHistoryQuery.formatHistory', () {
    test('summarizes bars and caps recent closes', () {
      final candles = [
        for (var i = 1; i <= 20; i++)
          Candle(
            time: DateTime.utc(2026, 1, i),
            close: 100.0 + i,
            high: 110.0 + i,
            low: 90.0 + i,
          ),
      ];
      final text = AgentHistoryQuery.formatHistory(
        symbol: 'AAPL',
        range: '1mo',
        interval: '1d',
        candles: candles,
      );
      expect(text, contains('History AAPL (1mo @ 1d): 20 bars'));
      expect(text, contains('change≈'));
      expect(text, contains('high≈'));
      expect(text, contains('Recent closes'));
      // Last 15 of 20 → starts at day 6.
      expect(text, contains('2026-01-06'));
      expect(text, isNot(contains('2026-01-05')));
      expect(text, contains('2026-01-20'));
    });

    test('intraday labels include time UTC', () {
      final text = AgentHistoryQuery.formatHistory(
        symbol: 'BTC_USD',
        range: '1d',
        interval: '15m',
        candles: [
          Candle(time: DateTime.utc(2026, 3, 1, 14, 30), close: 1),
          Candle(time: DateTime.utc(2026, 3, 1, 14, 45), close: 2),
        ],
      );
      expect(text, contains('2026-03-01 14:30 UTC'));
      expect(text, contains('2026-03-01 14:45 UTC'));
    });
  });
}
