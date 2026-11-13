import 'package:flutter/foundation.dart';

import '../../core/formatting.dart';
import 'user_config_keys.dart';
import 'user_config_store.dart';

/// How dense Markets / Crypto list rows should render.
enum ListDensity {
  /// Multi-line rows with name and source (default).
  comfortable,

  /// Tighter single-line rows for longer lists.
  compact,
}

/// Default history window when opening Asset detail.
enum ChartRangePreset {
  oneMonth,
  threeMonths,
  oneYear,
}

extension ChartRangePresetX on ChartRangePreset {
  /// Yahoo-style range key used by [MarketDataClient.getHistory].
  String get rangeKey => switch (this) {
        ChartRangePreset.oneMonth => '1mo',
        ChartRangePreset.threeMonths => '3mo',
        ChartRangePreset.oneYear => '1y',
      };

  /// Short chip / settings label.
  String get label => switch (this) {
        ChartRangePreset.oneMonth => '1M',
        ChartRangePreset.threeMonths => '3M',
        ChartRangePreset.oneYear => '1Y',
      };

  static ChartRangePreset? tryParse(String? raw) {
    return switch (raw) {
      '1mo' => ChartRangePreset.oneMonth,
      '3mo' => ChartRangePreset.threeMonths,
      '1y' => ChartRangePreset.oneYear,
      _ => null,
    };
  }
}

/// Persisted display preferences (lists, prices, chart default).
class DisplaySettings extends ChangeNotifier {
  DisplaySettings({this.store});

  UserConfigStore? store;
  ListDensity _listDensity = ListDensity.comfortable;
  PriceFormat _priceFormat = PriceFormat.full;
  ChartRangePreset _defaultChartRange = ChartRangePreset.oneMonth;
  bool _ready = false;

  ListDensity get listDensity => _listDensity;
  bool get isCompact => _listDensity == ListDensity.compact;
  PriceFormat get priceFormat => _priceFormat;
  ChartRangePreset get defaultChartRange => _defaultChartRange;
  bool get isReady => _ready;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    _applySlice(this.store?.getSlice(UserConfigKeys.display));
    _ready = true;
    notifyListeners();
  }

  Future<void> setListDensity(ListDensity density) async {
    if (_listDensity == density) return;
    _listDensity = density;
    notifyListeners();
    await _persist();
  }

  Future<void> setPriceFormat(PriceFormat format) async {
    if (_priceFormat == format) return;
    _priceFormat = format;
    notifyListeners();
    await _persist();
  }

  Future<void> setDefaultChartRange(ChartRangePreset range) async {
    if (_defaultChartRange == range) return;
    _defaultChartRange = range;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await store?.setSlice(UserConfigKeys.display, {
      'listDensity': _encodeDensity(_listDensity),
      'priceFormat': _encodePriceFormat(_priceFormat),
      'defaultChartRange': _defaultChartRange.rangeKey,
    });
  }

  void _applySlice(Object? slice) {
    if (slice == null) return;

    // Legacy: plain density string (pre-JSON display prefs).
    if (slice is String) {
      final legacyDensity = _parseDensity(slice);
      if (legacyDensity != null) {
        _listDensity = legacyDensity;
      }
      return;
    }

    if (slice is! Map) return;
    final map = Map<String, dynamic>.from(slice);
    _listDensity =
        _parseDensity(map['listDensity'] as String?) ?? ListDensity.comfortable;
    _priceFormat =
        _parsePriceFormat(map['priceFormat'] as String?) ?? PriceFormat.full;
    _defaultChartRange =
        ChartRangePresetX.tryParse(map['defaultChartRange'] as String?) ??
            ChartRangePreset.oneMonth;
  }

  static String _encodeDensity(ListDensity density) => switch (density) {
        ListDensity.comfortable => 'comfortable',
        ListDensity.compact => 'compact',
      };

  static ListDensity? _parseDensity(String? raw) {
    return switch (raw) {
      'comfortable' => ListDensity.comfortable,
      'compact' => ListDensity.compact,
      _ => null,
    };
  }

  static String _encodePriceFormat(PriceFormat format) => switch (format) {
        PriceFormat.full => 'full',
        PriceFormat.compact => 'compact',
      };

  static PriceFormat? _parsePriceFormat(String? raw) {
    return switch (raw) {
      'full' => PriceFormat.full,
      'compact' => PriceFormat.compact,
      _ => null,
    };
  }
}
