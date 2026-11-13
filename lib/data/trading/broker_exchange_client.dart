import 'broker_exchange.dart';
import 'order_models.dart';

/// Live order boundary for traditional / equity brokers.
///
/// Market data stays on [MarketDataClient]; this interface is write-only
/// (place / cancel / status). Register adapters in [BrokerExchangeRegistry].
abstract class BrokerExchangeClient {
  BrokerExchange get broker;

  /// Whether credentials are ready to place orders.
  bool get canPlaceOrders => false;

  /// Whether this broker should appear once credentials exist.
  bool get supportsLiveTrading => false;

  Future<OrderResult> placeOrder(OrderRequest request) {
    throw UnsupportedError(
      '${broker.displayName} does not support live order placement',
    );
  }

  Future<OrderResult> cancelOrder(String orderId) {
    throw UnsupportedError(
      '${broker.displayName} does not support cancel order',
    );
  }

  Future<OrderResult> getOrder(String orderId) {
    throw UnsupportedError(
      '${broker.displayName} does not support order status',
    );
  }
}
