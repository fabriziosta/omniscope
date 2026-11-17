import '../crypto/crypto_exchange_registry.dart';
import '../portfolio/portfolio_repository.dart';
import '../settings/data_source_settings.dart';
import '../settings/favorites_repository.dart';
import 'models.dart';

/// Symbols the app can open on [AssetDetailScreen] without a free-text search.
///
/// Includes the curated Markets watchlist, enabled crypto default pairs,
/// favorites / invest interest, and Practice holdings.
Set<String> knownAppSymbols({
  required CryptoExchangeRegistry cryptoRegistry,
  required FavoritesRepository favorites,
  required PortfolioRepository portfolio,
  DataSourceSettings? dataSources,
}) {
  final out = <String>{
    for (final symbol in defaultWatchlist) symbol.toUpperCase(),
    for (final symbol in favorites.symbols) symbol.toUpperCase(),
    for (final symbol in favorites.investInterestSymbols)
      symbol.toUpperCase(),
    for (final holding in portfolio.state.holdings)
      holding.symbol.toUpperCase(),
  };

  final clients = dataSources == null
      ? cryptoRegistry.exchanges
      : cryptoRegistry.enabledWhere(dataSources.isCryptoEnabled);
  for (final client in clients) {
    for (final symbol in client.exchange.defaultSymbols) {
      out.add(symbol.toUpperCase());
    }
  }
  return out;
}

/// Exact known-symbol tokens that appear in [text] (case-insensitive).
///
/// Tokens follow the same shape as [MarketContextBuilder.extractSymbolHint]
/// (`AAPL`, `BRK.B`, `BTC_USD`). Only symbols present in [known] are returned,
/// sorted alphabetically.
List<String> matchingKnownSymbolsInText(
  String text, {
  required Set<String> known,
}) {
  if (text.trim().isEmpty || known.isEmpty) return const [];

  final upper = text.toUpperCase();
  final tokens = RegExp(r'\b([A-Z]{1,5}(?:[._-][A-Z0-9]{1,10})?)\b')
      .allMatches(upper)
      .map((match) => match.group(1)!)
      .toSet();

  final list = tokens.intersection(known).toList()..sort();
  return list;
}
