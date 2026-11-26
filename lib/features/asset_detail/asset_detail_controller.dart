import 'package:flutter/foundation.dart';

import '../../core/app_copy.dart';
import '../../core/market_error_copy.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/settings/display_settings.dart';

typedef ChartRange = (String label, String range, String interval);

/// Screen-scoped quote + history loader for asset detail.
class AssetDetailController extends ChangeNotifier {
  AssetDetailController({
    required this.symbol,
    required this._marketData,
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

  /// Hover / a11y label for a [ranges] chip abbreviation.
  static String rangeTooltip(String shortLabel) {
    return switch (shortLabel) {
      '1M' => '1 month',
      '3M' => '3 months',
      '1Y' => '1 year',
      _ => shortLabel,
    };
  }

  /// One-line explainer under chart range chips.
  static String rangeExplainer(String shortLabel) {
    return switch (shortLabel) {
      '1M' => 'Daily closes for the last month.',
      '3M' => 'Daily closes for the last three months.',
      '1Y' => 'Daily closes for the last year.',
      _ => 'Daily closes for this period.',
    };
  }

  final String symbol;
  final MarketDataClient _marketData;

  var _rangeIndex = 0;
  Quote? _quote;
  List<Candle> _candles = const [];
  var _loading = true;
  var _hasError = false;
  String? _errorMessage;
  DateTime? _fetchedAt;
  var _loadGen = 0;

  int get rangeIndex => _rangeIndex;
  ChartRange get currentRange => ranges[_rangeIndex];
  Quote? get quote => _quote;
  List<Candle> get candles => _candles;
  bool get loading => _loading;
  bool get hasError => _hasError;
  DateTime? get fetchedAt => _fetchedAt;
  String get loadErrorMessage =>
      _errorMessage ?? AppCopy.checkConnection;

  Future<void> load() async {
    final gen = ++_loadGen;
    _loading = true;
    _hasError = false;
    _errorMessage = null;
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
      _errorMessage = null;
      _fetchedAt = DateTime.now();
      notifyListeners();
    } catch (e, st) {
      debugPrint('Asset detail load failed for $symbol: $e\n$st');
      if (gen != _loadGen) return;
      _hasError = true;
      _loading = false;
      _errorMessage = userFacingMarketError(e);
      notifyListeners();
    }
  }

  Future<void> setRange(int index) async {
    if (index < 0 || index >= ranges.length || index == _rangeIndex) return;
    _rangeIndex = index;
    // Keep the open quote; only the chart series changes with the range chip.
    if (_quote != null) {
      await _loadHistoryOnly();
    } else {
      await load();
    }
  }

  Future<void> _loadHistoryOnly() async {
    final gen = ++_loadGen;
    _loading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    final range = ranges[_rangeIndex];
    try {
      final candles = await _marketData.getHistory(
        symbol,
        range: range.$2,
        interval: range.$3,
      );
      if (gen != _loadGen) return;
      _candles = candles;
      _loading = false;
      _hasError = false;
      _errorMessage = null;
      _fetchedAt = DateTime.now();
      notifyListeners();
    } catch (e, st) {
      debugPrint('Asset detail history failed for $symbol: $e\n$st');
      if (gen != _loadGen) return;
      _hasError = true;
      _loading = false;
      _errorMessage = userFacingMarketError(e);
      notifyListeners();
    }
  }
}
