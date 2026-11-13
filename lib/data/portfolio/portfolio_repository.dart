import 'package:flutter/foundation.dart';

import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'models.dart';

class PortfolioRepository extends ChangeNotifier {
  PortfolioRepository({this.store});

  UserConfigStore? store;
  PortfolioState _state = PortfolioState.fresh();
  double _startingCash = PortfolioState.defaultStartingCash;
  bool _ready = false;

  PortfolioState get state => _state;
  double get startingCash => _startingCash;
  bool get isReady => _ready;

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.paperPortfolio);
    if (slice is! Map) {
      _startingCash = PortfolioState.defaultStartingCash;
      _state = PortfolioState.fresh(cash: _startingCash);
    } else {
      try {
        final map = Map<String, dynamic>.from(slice);
        final rawStart = map['startingCash'];
        if (rawStart is num && rawStart > 0) {
          _startingCash = rawStart.toDouble();
        } else {
          _startingCash = PortfolioState.defaultStartingCash;
        }
        _state = PortfolioState.fromJson(map);
      } catch (_) {
        _startingCash = PortfolioState.defaultStartingCash;
        _state = PortfolioState.fresh(cash: _startingCash);
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final map = _state.toJson();
    map['startingCash'] = _startingCash;
    await store?.setSlice(UserConfigKeys.paperPortfolio, map);
  }

  /// Updates the preferred starting cash for the next [reset] / fresh portfolio.
  /// Does not change current cash or holdings.
  Future<void> setStartingCash(double amount) async {
    if (amount <= 0 || amount.isNaN) return;
    if ((_startingCash - amount).abs() < 1e-9) return;
    _startingCash = amount;
    notifyListeners();
    await _persist();
  }

  Future<TradeResult> buy({
    required String symbol,
    required double shares,
    required double price,
  }) async {
    if (shares <= 0) {
      return const TradeResult.fail('Share quantity must be positive.');
    }
    if (price <= 0) {
      return const TradeResult.fail('Price must be positive.');
    }

    final cost = shares * price;
    if (cost > _state.cash + 1e-9) {
      return const TradeResult.fail('Not enough cash for this purchase.');
    }

    final holdings = List<Holding>.from(_state.holdings);
    final index = holdings.indexWhere((h) => h.symbol == symbol);
    if (index >= 0) {
      final existing = holdings[index];
      final totalShares = existing.shares + shares;
      final avgCost =
          ((existing.shares * existing.avgCost) + cost) / totalShares;
      holdings[index] = existing.copyWith(shares: totalShares, avgCost: avgCost);
    } else {
      holdings.add(Holding(symbol: symbol, shares: shares, avgCost: price));
    }

    _state = PortfolioState(cash: _state.cash - cost, holdings: holdings);
    await _persist();
    notifyListeners();
    return TradeResult.ok(_state);
  }

  Future<TradeResult> sell({
    required String symbol,
    required double shares,
    required double price,
  }) async {
    if (shares <= 0) {
      return const TradeResult.fail('Share quantity must be positive.');
    }
    if (price <= 0) {
      return const TradeResult.fail('Price must be positive.');
    }

    final holdings = List<Holding>.from(_state.holdings);
    final index = holdings.indexWhere((h) => h.symbol == symbol);
    if (index < 0) {
      return const TradeResult.fail('You do not hold this symbol.');
    }

    final existing = holdings[index];
    if (shares > existing.shares + 1e-9) {
      return const TradeResult.fail('Not enough shares to sell.');
    }

    final proceeds = shares * price;
    final remaining = existing.shares - shares;
    if (remaining <= 1e-9) {
      holdings.removeAt(index);
    } else {
      holdings[index] = existing.copyWith(shares: remaining);
    }

    _state = PortfolioState(cash: _state.cash + proceeds, holdings: holdings);
    await _persist();
    notifyListeners();
    return TradeResult.ok(_state);
  }

  Future<void> reset() async {
    _state = PortfolioState.fresh(cash: _startingCash);
    await _persist();
    notifyListeners();
  }
}
