import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/models.dart';

/// Shared [MarketDataClient] stub for unit/widget tests.
class FakeMarketDataClient implements MarketDataClient {
  FakeMarketDataClient({
    this.delay = Duration.zero,
    this.fail = false,
    this.basePrice = 100,
    this.scalePriceByCall = false,
    this.emptyQuotes = false,
    this.emptyHistory = false,
    this.fixedName,
    this.namePrefix,
    this.previousClose,
    this.change,
    this.changePercent,
    this.exchange,
    this.exchangeFor,
    this.dataSource,
    this.dataSourceId,
    this.history,
    this.historyBuilder,
  });

  Duration delay;
  bool fail;

  /// Base quote price. When [scalePriceByCall] is true, price is
  /// `basePrice * calls` after each [getQuotes] increments the counter.
  final double basePrice;
  final bool scalePriceByCall;

  final bool emptyQuotes;
  final bool emptyHistory;

  /// When set, every quote uses this name; otherwise [namePrefix] + symbol,
  /// or the symbol itself when both are null.
  final String? fixedName;
  final String? namePrefix;

  final double? previousClose;
  final double? change;
  final double? changePercent;
  final String? exchange;
  final String? Function(String symbol)? exchangeFor;
  final String? dataSource;
  final String? dataSourceId;

  /// Fixed history returned for every symbol when [historyBuilder] is null.
  final List<Candle>? history;
  final List<Candle> Function(String symbol)? historyBuilder;

  var calls = 0;
  int get quoteCalls => calls;
  final requestedBatches = <List<String>>[];

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    calls += 1;
    requestedBatches.add(List<String>.from(symbols));
    final call = calls;
    await Future<void>.delayed(delay);
    if (fail) throw Exception('network');
    if (emptyQuotes) return const [];
    final price = scalePriceByCall ? basePrice * call : basePrice;
    return [
      for (final s in symbols)
        Quote(
          symbol: s,
          price: price,
          name: fixedName ??
              (namePrefix != null ? '$namePrefix$s' : s),
          previousClose: previousClose,
          change: change,
          changePercent: changePercent,
          exchange: exchangeFor?.call(s) ?? exchange,
          dataSource: dataSource,
          dataSourceId: dataSourceId,
        ),
    ];
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) async {
    await Future<void>.delayed(delay);
    if (fail) throw Exception('network');
    if (emptyHistory) return const [];
    if (historyBuilder != null) return historyBuilder!(symbol);
    if (history != null) return history!;
    return [
      Candle(time: DateTime.utc(2026, 1, 1), close: 100),
      Candle(time: DateTime.utc(2026, 1, 2), close: 110),
    ];
  }
}
