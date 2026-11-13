/// Live balances from a connected crypto exchange (read-only snapshot).
class ExchangePortfolioSnapshot {
  const ExchangePortfolioSnapshot({
    required this.exchangeId,
    required this.exchangeName,
    required this.balances,
    this.totalValue,
    this.availableValue,
    this.currency = 'USD',
  });

  final String exchangeId;
  final String exchangeName;

  /// Account total when the venue reports one (e.g. cash balance in [currency]).
  final double? totalValue;

  /// Available / withdrawable total when reported.
  final double? availableValue;

  /// Quote currency for [totalValue] / [availableValue] (usually USD).
  final String currency;

  /// Non-zero per-asset balances.
  final List<ExchangeBalance> balances;

  double get holdingsValue => balances.fold<double>(
        0,
        (sum, b) => sum + (b.marketValue ?? 0),
      );
}

/// One asset row inside an [ExchangePortfolioSnapshot].
class ExchangeBalance {
  const ExchangeBalance({
    required this.asset,
    required this.quantity,
    this.marketValue,
    this.available,
    this.reserved,
  });

  /// Venue asset code (e.g. `BTC`, `USD`, `USDT`).
  final String asset;

  /// Total quantity held.
  final double quantity;

  /// Mark-to-market value in account currency when provided.
  final double? marketValue;

  /// Quantity free for orders / withdrawals.
  final double? available;

  /// Quantity locked (open orders, etc.).
  final double? reserved;
}
