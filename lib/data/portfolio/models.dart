class Holding {
  const Holding({
    required this.symbol,
    required this.shares,
    required this.avgCost,
  });

  final String symbol;
  final double shares;
  final double avgCost;

  double get costBasis => shares * avgCost;

  Holding copyWith({String? symbol, double? shares, double? avgCost}) {
    return Holding(
      symbol: symbol ?? this.symbol,
      shares: shares ?? this.shares,
      avgCost: avgCost ?? this.avgCost,
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'shares': shares,
        'avgCost': avgCost,
      };

  factory Holding.fromJson(Map<String, dynamic> json) {
    return Holding(
      symbol: json['symbol'] as String,
      shares: (json['shares'] as num).toDouble(),
      avgCost: (json['avgCost'] as num).toDouble(),
    );
  }
}

class PortfolioState {
  const PortfolioState({
    required this.cash,
    required this.holdings,
  });

  final double cash;
  final List<Holding> holdings;

  /// Default practice cash when no custom starting amount is configured.
  static const defaultStartingCash = 10000.0;

  /// Alias kept for call sites that still use the old name.
  static const startingCash = defaultStartingCash;

  factory PortfolioState.fresh({
    double cash = defaultStartingCash,
  }) =>
      PortfolioState(
        cash: cash,
        holdings: const [],
      );

  Holding? holdingFor(String symbol) {
    for (final h in holdings) {
      if (h.symbol == symbol) return h;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'cash': cash,
        'holdings': holdings.map((h) => h.toJson()).toList(),
      };

  factory PortfolioState.fromJson(Map<String, dynamic> json) {
    final raw = json['holdings'] as List? ?? const [];
    return PortfolioState(
      cash: (json['cash'] as num).toDouble(),
      holdings: raw
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum TradeSide { buy, sell }

class TradeResult {
  const TradeResult.ok(this.state) : error = null;
  const TradeResult.fail(this.error) : state = null;

  final PortfolioState? state;
  final String? error;

  bool get success => state != null;
}
