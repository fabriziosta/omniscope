/// Side for live exchange orders (not paper).
enum OrderSide {
  buy,
  sell,
}

extension OrderSideX on OrderSide {
  String get label => switch (this) {
        OrderSide.buy => 'Buy',
        OrderSide.sell => 'Sell',
      };

  String get apiValue => name.toUpperCase();

  static OrderSide? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'buy' => OrderSide.buy,
      'sell' => OrderSide.sell,
      _ => null,
    };
  }
}

enum OrderType {
  market,
  limit,
}

/// Request to place a live order on a connected exchange.
class OrderRequest {
  const OrderRequest({
    required this.exchangeId,
    required this.symbol,
    required this.side,
    required this.quantity,
    this.type = OrderType.market,
    this.limitPrice,
    this.clientOrderId,
  });

  final String exchangeId;
  final String symbol;
  final OrderSide side;
  final double quantity;
  final OrderType type;
  final double? limitPrice;
  final String? clientOrderId;
}

/// Result of a live order submission (or failure).
class OrderResult {
  const OrderResult.ok({
    required this.orderId,
    this.rawStatus,
    this.message,
  }) : error = null;

  const OrderResult.fail(this.error)
      : orderId = null,
        rawStatus = null,
        message = null;

  final String? orderId;
  final String? rawStatus;
  final String? message;
  final String? error;

  bool get success => error == null && orderId != null;
}
