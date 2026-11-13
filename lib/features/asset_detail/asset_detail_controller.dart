import 'package:flutter/foundation.dart';

import '../../core/app_copy.dart';
import '../../core/formatting.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/display_settings.dart';

typedef ChartRange = (String label, String range, String interval);

/// Result of a paper trade attempt for the UI to toast.
class AssetTradeUiResult {
  const AssetTradeUiResult({
    required this.success,
    required this.buy,
    required this.shares,
    required this.symbol,
    this.error,
  });

  final bool success;
  final bool buy;
  final double shares;
  final String symbol;
  final String? error;

  String get title {
    if (!success) return 'Trade failed';
    return buy ? 'Buy complete' : 'Sell complete';
  }

  String get description {
    if (!success) {
      return error ?? 'Could not complete that trade.';
    }
    final qty = formatShares(shares);
    return buy
        ? 'Bought $qty $symbol (paper).'
        : 'Sold $qty $symbol (paper).';
  }
}

/// Screen-scoped quote + history loader and paper trade orchestration.
class AssetDetailController extends ChangeNotifier {
  AssetDetailController({
    required this.symbol,
    required this._marketData,
    required this._portfolio,
    required ChartRangePreset initialRange,
  }) {
    final idx = ranges.indexWhere((r) => r.$2 == initialRange.rangeKey);
    _rangeIndex = idx >= 0 ? idx : 0;
  }

  static const ranges = <ChartRange>[
    ('1M', '1mo', '1d'),
    ('3M', '3mo', '1d'),
    ('1Y', '1y', '1d'),
  ];

  final String symbol;
  final MarketDataClient _marketData;
  final PortfolioRepository _portfolio;

  var _rangeIndex = 0;
  Quote? _quote;
  List<Candle> _candles = const [];
  var _loading = true;
  var _hasError = false;
  var _loadGen = 0;

  int get rangeIndex => _rangeIndex;
  ChartRange get currentRange => ranges[_rangeIndex];
  Quote? get quote => _quote;
  List<Candle> get candles => _candles;
  bool get loading => _loading;
  bool get hasError => _hasError;

  Future<void> load() async {
    final gen = ++_loadGen;
    _loading = true;
    _hasError = false;
    notifyListeners();

    final range = ranges[_rangeIndex];
    try {
      final results = await Future.wait([
        _marketData.getQuotes([symbol]),
        _marketData.getHistory(
          symbol,
          range: range.$2,
          interval: range.$3,
        ),
      ]);
      if (gen != _loadGen) return;
      _quote = (results[0] as List<Quote>).first;
      _candles = results[1] as List<Candle>;
      _loading = false;
      _hasError = false;
      notifyListeners();
    } catch (e, st) {
      debugPrint('Asset detail load failed for $symbol: $e\n$st');
      if (gen != _loadGen) return;
      _hasError = true;
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setRange(int index) async {
    if (index < 0 || index >= ranges.length || index == _rangeIndex) return;
    _rangeIndex = index;
    await load();
  }

  /// Parses shares and executes a paper trade. Returns null if quantity invalid.
  Future<AssetTradeUiResult?> trade({
    required bool buy,
    required String sharesText,
  }) async {
    final quote = _quote;
    if (quote == null) return null;

    final raw = sharesText.trim().replaceAll(',', '');
    final shares = double.tryParse(raw);
    if (shares == null || shares <= 0) {
      return null;
    }

    final result = buy
        ? await _portfolio.buy(
            symbol: quote.symbol,
            shares: shares,
            price: quote.price,
          )
        : await _portfolio.sell(
            symbol: quote.symbol,
            shares: shares,
            price: quote.price,
          );

    return AssetTradeUiResult(
      success: result.success,
      buy: buy,
      shares: shares,
      symbol: quote.symbol,
      error: result.error,
    );
  }

  String get loadErrorMessage => AppCopy.checkConnection;
}
