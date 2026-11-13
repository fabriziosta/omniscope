import '../crypto/crypto_exchange_client.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../settings/data_source_settings.dart';
import 'equity_data_source.dart';
import 'market_data_client.dart';
import 'models.dart';

/// Routes symbols to enabled equities providers or a registered crypto exchange.
class RoutingMarketDataClient implements MarketDataClient {
  RoutingMarketDataClient({
    required this.equitiesRegistry,
    required this.cryptoRegistry,
    required this.dataSources,
  });

  final EquityDataSourceRegistry equitiesRegistry;
  final CryptoExchangeRegistry cryptoRegistry;
  final DataSourceSettings dataSources;

  List<EquityDataSourceEntry> get _enabledEquities =>
      equitiesRegistry.enabledWhere(dataSources.isMarketEnabled);

  CryptoExchangeClient? _cryptoForSymbol(String symbol) {
    final client = cryptoRegistry.clientForSymbol(symbol);
    if (client == null) return null;
    if (!dataSources.isCryptoEnabled(client.exchange.id)) return null;
    return client;
  }

  @override
  Future<List<Quote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return const [];

    final cryptoByClient = <CryptoExchangeClient, List<String>>{};
    final equitySymbols = <String>[];

    for (final symbol in symbols) {
      final crypto = _cryptoForSymbol(symbol);
      if (crypto != null) {
        cryptoByClient.putIfAbsent(crypto, () => <String>[]).add(symbol);
      } else {
        equitySymbols.add(symbol);
      }
    }

    final quotes = <Quote>[];
    Object? lastError;

    for (final entry in cryptoByClient.entries) {
      try {
        quotes.addAll(await entry.key.getQuotes(entry.value));
      } catch (e) {
        lastError = e;
      }
    }

    if (equitySymbols.isNotEmpty) {
      final equities = _enabledEquities;
      if (equities.isEmpty) {
        lastError ??= MarketDataException(
          'No equities data sources enabled. Turn one on in Settings.',
        );
      } else {
        // First enabled provider wins until multi-provider merge exists.
        try {
          quotes.addAll(await equities.first.client.getQuotes(equitySymbols));
        } catch (e) {
          lastError = e;
        }
      }
    }

    if (quotes.isEmpty && lastError != null) {
      throw lastError;
    }
    return quotes;
  }

  @override
  Future<List<Candle>> getHistory(
    String symbol, {
    required String range,
    required String interval,
  }) {
    final crypto = _cryptoForSymbol(symbol);
    if (crypto != null) {
      return crypto.getHistory(
        symbol,
        range: range,
        interval: interval,
      );
    }

    final equities = _enabledEquities;
    if (equities.isEmpty) {
      return Future.error(
        MarketDataException(
          'No equities data sources enabled. Turn one on in Settings.',
        ),
      );
    }
    return equities.first.client.getHistory(
      symbol,
      range: range,
      interval: interval,
    );
  }
}
