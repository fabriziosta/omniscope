import 'package:flutter/foundation.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/portfolio/models.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/venues/exchange_portfolio.dart';
import '../../data/venues/live_venue_capabilities.dart';

/// Screen-scoped portfolio quotes + live balances with race-safe loads.
class PortfolioScreenController extends ChangeNotifier {
  PortfolioScreenController({
    required this._marketData,
    required this._portfolio,
    required this._cryptoRegistry,
    required this._dataSources,
    this._brokerRegistry = BrokerExchangeRegistry.empty,
  });

  final MarketDataClient _marketData;
  final PortfolioRepository _portfolio;
  final CryptoExchangeRegistry _cryptoRegistry;
  final BrokerExchangeRegistry _brokerRegistry;
  final DataSourceSettings _dataSources;

  List<String> _syncedLiveIds = const [];

  Map<String, Quote> _quotes = const {};
  var _loadingQuotes = false;
  String? _quoteError;
  var _quotesGen = 0;

  final Map<String, ExchangePortfolioSnapshot> _liveByExchange = {};
  final Map<String, String> _liveErrors = {};
  var _loadingLive = false;
  var _liveGen = 0;
  var _disposed = false;

  Map<String, Quote> get quotes => _quotes;
  bool get loadingQuotes => _loadingQuotes;
  String? get quoteError => _quoteError;

  Map<String, ExchangePortfolioSnapshot> get liveByExchange =>
      Map.unmodifiable(_liveByExchange);
  Map<String, String> get liveErrors => Map.unmodifiable(_liveErrors);
  bool get loadingLive => _loadingLive;
  bool get isRefreshing => _loadingQuotes || _loadingLive;

  List<LiveVenueCapabilities> get liveClients => [
        for (final c in _cryptoRegistry.portfolioClientsWhere(
          _dataSources.isCryptoEnabled,
        ))
          c,
        for (final c in _brokerRegistry.portfolioClientsWhere(
          _dataSources.isBrokerEnabled,
        ))
          c,
      ];

  List<LiveVenueCapabilities> get pendingLiveClients => [
        for (final c in _cryptoRegistry.enabledWhere(
          _dataSources.isCryptoEnabled,
        ))
          if (c.supportsLivePortfolio && !c.canFetchPortfolio) c,
        for (final c in _brokerRegistry.enabledWhere(
          _dataSources.isBrokerEnabled,
        ))
          if (c.supportsLivePortfolio && !c.canFetchPortfolio) c,
      ];

  List<PortfolioDescriptor> get portfolios => PortfolioCatalog.list(
        registry: _cryptoRegistry,
        brokerRegistry: _brokerRegistry,
        dataSources: _dataSources,
      );

  bool get hasLive => liveClients.isNotEmpty;

  /// Re-fetch live balances when the set of ready venues changes (e.g. after
  /// saving credentials without leaving the Portfolio tab).
  ///
  /// Safe to call from [build]; the fetch is scheduled off the build phase.
  void syncLiveClientsIfNeeded() {
    final ids = [
      for (final c in liveClients) c.venueId,
    ];
    if (_listEquals(ids, _syncedLiveIds)) return;
    _syncedLiveIds = List<String>.unmodifiable(ids);
    Future.microtask(refreshLivePortfolios);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  double holdingsValueFor(PortfolioState state) {
    var value = 0.0;
    for (final h in state.holdings) {
      final price = _quotes[h.symbol]?.price ?? h.avgCost;
      value += h.shares * price;
    }
    return value;
  }

  double costBasisFor(PortfolioState state) {
    var basis = 0.0;
    for (final h in state.holdings) {
      basis += h.costBasis;
    }
    return basis;
  }

  double paperTotalFor(PortfolioState state) =>
      state.cash + holdingsValueFor(state);

  double unrealizedFor(PortfolioState state) =>
      holdingsValueFor(state) - costBasisFor(state);

  Future<void> refreshAll() async {
    await Future.wait([
      refreshQuotes(),
      refreshLivePortfolios(),
    ]);
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _quotesGen++;
    _liveGen++;
    super.dispose();
  }

  Future<void> refreshQuotes() async {
    final gen = ++_quotesGen;
    final symbols = _portfolio.state.holdings
        .map((h) => h.symbol)
        .toList(growable: false);
    if (symbols.isEmpty) {
      if (gen != _quotesGen) return;
      _quotes = const {};
      _quoteError = null;
      _loadingQuotes = false;
      _emit();
      return;
    }

    _loadingQuotes = true;
    _quoteError = null;
    _emit();

    try {
      final list = await _marketData.getQuotes(symbols);
      if (gen != _quotesGen) return;
      _quotes = {for (final q in list) q.symbol: q};
      _loadingQuotes = false;
      _emit();
    } catch (e, st) {
      debugPrint('Portfolio quotes failed: $e\n$st');
      if (gen != _quotesGen) return;
      _quoteError = AppCopy.portfolioQuoteError;
      _loadingQuotes = false;
      _emit();
    }
  }

  Future<void> refreshLivePortfolios() async {
    final gen = ++_liveGen;
    final clients = liveClients;
    _syncedLiveIds = [
      for (final c in clients) c.venueId,
    ];
    if (clients.isEmpty) {
      if (gen != _liveGen) return;
      _liveByExchange.clear();
      _liveErrors.clear();
      _loadingLive = false;
      _emit();
      return;
    }

    _loadingLive = true;
    _liveErrors.clear();
    _emit();

    final next = <String, ExchangePortfolioSnapshot>{};
    final errors = <String, String>{};
    await Future.wait([
      for (final client in clients) _loadOneLive(client, next, errors),
    ]);

    if (gen != _liveGen) return;
    _liveByExchange
      ..clear()
      ..addAll(next);
    _liveErrors
      ..clear()
      ..addAll(errors);
    _loadingLive = false;
    _emit();
  }

  Future<void> _loadOneLive(
    LiveVenueCapabilities client,
    Map<String, ExchangePortfolioSnapshot> next,
    Map<String, String> errors,
  ) async {
    try {
      next[client.venueId] = await client.fetchPortfolio();
    } catch (e, st) {
      debugPrint('Live portfolio ${client.venueId} failed: $e\n$st');
      errors[client.venueId] =
          'Could not load ${client.displayName} balances.';
    }
  }
}
