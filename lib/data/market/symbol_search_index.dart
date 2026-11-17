import '../crypto/crypto_exchange_registry.dart';
import '../portfolio/portfolio_repository.dart';
import '../settings/data_source_settings.dart';
import '../settings/favorites_repository.dart';
import 'known_app_symbols.dart';
import 'market_data_client.dart';
import 'market_data_links.dart';
import 'models.dart';

/// One row in the global shell symbol search index.
class SymbolSearchEntry {
  const SymbolSearchEntry({
    required this.symbol,
    this.name,
    this.kindLabel,
  });

  final String symbol;
  final String? name;
  final String? kindLabel;

  SymbolSearchEntry copyWith({
    String? symbol,
    String? name,
    String? kindLabel,
    bool clearName = false,
  }) {
    return SymbolSearchEntry(
      symbol: symbol ?? this.symbol,
      name: clearName ? null : (name ?? this.name),
      kindLabel: kindLabel ?? this.kindLabel,
    );
  }
}

/// Offline display name for [symbol] when no live [Quote.name] is available.
String? offlineSymbolDisplayName(String symbol) {
  final pair = pairLabelFromSymbol(symbol);
  if (pair != null) return pair;
  return wikipediaDisplayName(symbol);
}

String? _kindLabelForSymbol(
  String symbol, {
  required CryptoExchangeRegistry cryptoRegistry,
}) {
  final kind = watchlistKindBySymbol[symbol] ??
      watchlistKindBySymbol[symbol.toUpperCase()];
  if (kind != null) return kind.label;
  if (cryptoRegistry.handlesSymbol(symbol) ||
      pairLabelFromSymbol(symbol) != null) {
    return MarketAssetKind.crypto.label;
  }
  return null;
}

/// Build a searchable catalog from [knownAppSymbols] plus optional extras.
List<SymbolSearchEntry> buildSymbolSearchEntries({
  required CryptoExchangeRegistry cryptoRegistry,
  required FavoritesRepository favorites,
  required PortfolioRepository portfolio,
  DataSourceSettings? dataSources,
  Iterable<String> extraSymbols = const [],
  Map<String, String?> namesBySymbol = const {},
}) {
  final symbols = knownAppSymbols(
    cryptoRegistry: cryptoRegistry,
    favorites: favorites,
    portfolio: portfolio,
    dataSources: dataSources,
  );
  for (final symbol in extraSymbols) {
    final trimmed = symbol.trim();
    if (trimmed.isNotEmpty) symbols.add(trimmed.toUpperCase());
  }

  final sorted = symbols.toList()..sort();
  return [
    for (final symbol in sorted)
      SymbolSearchEntry(
        symbol: symbol,
        name: namesBySymbol[symbol] ??
            namesBySymbol[symbol.toUpperCase()] ??
            offlineSymbolDisplayName(symbol),
        kindLabel: _kindLabelForSymbol(
          symbol,
          cryptoRegistry: cryptoRegistry,
        ),
      ),
  ];
}

/// Case-insensitive substring filter on symbol and optional display name.
List<SymbolSearchEntry> filterSymbolSearchEntries(
  List<SymbolSearchEntry> entries,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return [
    for (final entry in entries)
      if (entry.symbol.toLowerCase().contains(q) ||
          (entry.name?.toLowerCase().contains(q) ?? false))
        entry,
  ];
}

/// Merge live crypto spot catalogs from enabled venues into [symbols].
Future<Set<String>> mergeCryptoBrowseSymbols({
  required CryptoExchangeRegistry cryptoRegistry,
  DataSourceSettings? dataSources,
  Set<String>? into,
}) async {
  final out = into ?? <String>{};
  final clients = dataSources == null
      ? cryptoRegistry.exchanges
      : cryptoRegistry.enabledWhere(dataSources.isCryptoEnabled);
  for (final client in clients) {
    try {
      final browsed = await client.browseSymbols();
      for (final symbol in browsed) {
        final trimmed = symbol.trim();
        if (trimmed.isNotEmpty) out.add(trimmed.toUpperCase());
      }
    } catch (_) {
      // Keep curated defaults — browse is best-effort enrichment.
    }
  }
  return out;
}

const _enrichChunkSize = 40;

/// Soft-fetch [Quote.name] for [symbols]; failures are ignored.
Future<Map<String, String>> enrichSymbolDisplayNames({
  required MarketDataClient marketData,
  required Iterable<String> symbols,
  int chunkSize = _enrichChunkSize,
}) async {
  final names = <String, String>{};
  final list = [
    for (final symbol in symbols)
      if (symbol.trim().isNotEmpty) symbol.trim(),
  ];
  if (list.isEmpty) return names;

  for (var i = 0; i < list.length; i += chunkSize) {
    final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
    final chunk = list.sublist(i, end);
    try {
      final quotes = await marketData.getQuotes(chunk);
      for (final quote in quotes) {
        final name = quote.name?.trim();
        if (name == null || name.isEmpty) continue;
        names[quote.symbol.toUpperCase()] = name;
      }
    } catch (_) {
      // Name enrichment is optional; keep offline labels.
    }
  }
  return names;
}

/// Apply [namesBySymbol] onto entries (upper-cased keys). Prefer live names.
List<SymbolSearchEntry> applyDisplayNames(
  List<SymbolSearchEntry> entries,
  Map<String, String> namesBySymbol,
) {
  if (namesBySymbol.isEmpty) return entries;
  return [
    for (final entry in entries)
      SymbolSearchEntry(
        symbol: entry.symbol,
        name: namesBySymbol[entry.symbol.toUpperCase()] ?? entry.name,
        kindLabel: entry.kindLabel,
      ),
  ];
}
