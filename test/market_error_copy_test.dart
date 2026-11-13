import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/app_copy.dart';
import 'package:omniscope/core/market_error_copy.dart';
import 'package:omniscope/data/market/market_data_client.dart';

void main() {
  test('web CORS-like errors use the web hint', () {
    final message = userFacingMarketError(
      MarketDataException('Yahoo/CORS proxy error for AAPL: blocked'),
      forWeb: true,
    );
    expect(message, AppCopy.webMarketDataHint);
  });

  test('native failures fall back to check connection', () {
    final message = userFacingMarketError(
      MarketDataException('Yahoo returned 500 for AAPL'),
      forWeb: false,
    );
    expect(message, AppCopy.checkConnection);
  });
}
