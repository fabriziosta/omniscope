import '../../trading/order_models.dart';
import '../../venues/exchange_portfolio.dart';

/// Maps Alpaca Trading API JSON → Omniscope domain models.
abstract final class AlpacaDto {
  static ExchangePortfolioSnapshot portfolioFromAccountAndPositions({
    required String exchangeId,
    required String exchangeName,
    required Map<String, dynamic> account,
    required List<dynamic> positions,
  }) {
    final currency = _str(account['currency']) ?? 'USD';
    final equity = _num(account['equity']);
    final cash = _num(account['cash']);
    final buyingPower = _num(account['buying_power']);

    final balances = <ExchangeBalance>[];
    if (cash != null && cash != 0) {
      balances.add(
        ExchangeBalance(
          asset: currency,
          quantity: cash,
          marketValue: cash,
          available: buyingPower ?? cash,
        ),
      );
    }

    for (final raw in positions) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final symbol = _str(map['symbol']);
      if (symbol == null || symbol.isEmpty) continue;
      final qty = _num(map['qty']) ?? _num(map['qty_available']) ?? 0;
      if (qty == 0) continue;
      final marketValue = _num(map['market_value']);
      final available = _num(map['qty_available']) ?? qty;
      balances.add(
        ExchangeBalance(
          asset: symbol,
          quantity: qty,
          marketValue: marketValue,
          available: available,
        ),
      );
    }

    return ExchangePortfolioSnapshot(
      exchangeId: exchangeId,
      exchangeName: exchangeName,
      balances: balances,
      totalValue: equity,
      availableValue: buyingPower ?? cash,
      currency: currency,
    );
  }

  static OrderResult orderResultFromJson(Map<String, dynamic> json) {
    final id = _str(json['id']);
    if (id == null || id.isEmpty) {
      return const OrderResult.fail('Alpaca order response missing id');
    }
    return OrderResult.ok(
      orderId: id,
      rawStatus: _str(json['status']),
      message: _str(json['order_type']),
    );
  }

  static Map<String, dynamic> placeOrderBody(OrderRequest request) {
    final body = <String, dynamic>{
      'symbol': request.symbol.trim().toUpperCase(),
      'qty': _qtyString(request.quantity),
      'side': request.side == OrderSide.buy ? 'buy' : 'sell',
      'type': request.type == OrderType.limit ? 'limit' : 'market',
      'time_in_force': 'day',
    };
    if (request.type == OrderType.limit && request.limitPrice != null) {
      body['limit_price'] = request.limitPrice!.toString();
    }
    final clientId = request.clientOrderId?.trim();
    if (clientId != null && clientId.isNotEmpty) {
      body['client_order_id'] = clientId;
    }
    return body;
  }

  static String _qtyString(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity.toString();
  }

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
