import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_copy.dart';
import '../data/market/market_data_client.dart';

/// Maps raw market-data failures to short, learner-friendly copy.
String userFacingMarketError(Object error, {bool forWeb = kIsWeb}) {
  if (forWeb) {
    final raw = error is MarketDataException
        ? error.message
        : error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('cors') ||
        lower.contains('proxy') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('xmlhttprequest') ||
        lower.contains('clientexception')) {
      return AppCopy.webMarketDataHint;
    }
  }
  if (error is MarketDataException && error.message.trim().isNotEmpty) {
    final msg = error.message.trim();
    // Keep provider messages short when they are already user-facing.
    if (msg.contains('No equities data sources enabled')) {
      return AppCopy.noMarketSourcesEnabled;
    }
  }
  return AppCopy.checkConnection;
}
