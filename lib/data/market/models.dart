class Quote {
  const Quote({
    required this.symbol,
    required this.price,
    this.name,
    this.currency,
    this.previousClose,
    this.change,
    this.changePercent,
    this.exchange,
    this.dataSource,
    this.dataSourceId,
  });

  final String symbol;
  final String? name;
  final double price;
  final String? currency;
  final double? previousClose;
  final double? change;
  final double? changePercent;

  /// Listing venue when known (e.g. `NMS`, `XETRA`) — not the data provider.
  final String? exchange;

  /// Where this live quote was fetched (e.g. `Yahoo Finance`, `Crypto.com`).
  final String? dataSource;

  /// Stable provider id for attribution links (e.g. `yahoo`, `crypto_com`).
  final String? dataSourceId;

  bool get isUp => (change ?? 0) >= 0;

  /// Compact identity line for list rows (name / pair · venue).
  ///
  /// Prefer a human name when it adds information beyond [symbol]; fall back to
  /// `BASE / QUOTE` for underscore pairs (e.g. `BTC_USD`). Append [exchange]
  /// when present so the asset is identifiable before opening detail.
  String? get listSubtitle {
    final bits = <String>[];
    final pairLabel = _pairLabelFromSymbol(symbol);
    final rawName = name?.trim();
    if (rawName != null && rawName.isNotEmpty) {
      final upper = rawName.toUpperCase();
      final sameAsSymbol = upper == symbol.toUpperCase();
      final sameAsPairBase = pairLabel != null &&
          upper == pairLabel.split(' / ').first.toUpperCase();
      if (!sameAsSymbol && !sameAsPairBase) {
        bits.add(rawName);
      } else if (pairLabel != null) {
        bits.add(pairLabel);
      }
    } else if (pairLabel != null) {
      bits.add(pairLabel);
    }

    final venue = exchange?.trim();
    if (venue != null &&
        venue.isNotEmpty &&
        (bits.isEmpty || bits.last.toUpperCase() != venue.toUpperCase())) {
      bits.add(venue);
    }
    if (bits.isEmpty) return null;
    return bits.join(' · ');
  }
}

/// `BTC_USD` → `BTC / USD`; returns null when [symbol] is not a pair.
String? _pairLabelFromSymbol(String symbol) {
  final parts = symbol.split('_');
  if (parts.length < 2) return null;
  final base = parts.first.trim();
  final quote = parts.sublist(1).join('_').trim();
  if (base.isEmpty || quote.isEmpty) return null;
  return '$base / $quote';
}

class Candle {
  const Candle({
    required this.time,
    required this.close,
    this.open,
    this.high,
    this.low,
    this.volume,
  });

  final DateTime time;
  final double close;
  final double? open;
  final double? high;
  final double? low;
  final double? volume;
}

/// Top-level Markets groups (asset kind).
enum MarketAssetKind {
  indices,
  etfs,
  stocks,
  crypto,
}

extension MarketAssetKindLabel on MarketAssetKind {
  String get label => switch (this) {
        MarketAssetKind.indices => 'Indices',
        MarketAssetKind.etfs => 'ETFs',
        MarketAssetKind.stocks => 'Stocks',
        MarketAssetKind.crypto => 'Crypto',
      };
}

/// Curated watchlist row with a fixed asset group.
class WatchlistEntry {
  const WatchlistEntry({
    required this.symbol,
    required this.kind,
  });

  final String symbol;
  final MarketAssetKind kind;
}

/// Default curated watchlist for the Markets home screen (Yahoo symbols).
///
/// Yahoo has no stable free “list all equities” API, so Markets browse is a
/// curated catalog. Quotes load in pages via [QuotesListController].
const defaultWatchlistEntries = <WatchlistEntry>[
  // Indices
  WatchlistEntry(symbol: '^GSPC', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^DJI', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^IXIC', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^RUT', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^VIX', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^FTSE', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^GDAXI', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^FCHI', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^N225', kind: MarketAssetKind.indices),
  WatchlistEntry(symbol: '^HSI', kind: MarketAssetKind.indices),
  // ETFs
  WatchlistEntry(symbol: 'SPY', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'QQQ', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'IWM', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'DIA', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'VTI', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'VOO', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'VEA', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'VWO', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'AGG', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'BND', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'GLD', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'SLV', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'XLF', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'XLK', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'XLE', kind: MarketAssetKind.etfs),
  WatchlistEntry(symbol: 'ARKK', kind: MarketAssetKind.etfs),
  // Stocks — US
  WatchlistEntry(symbol: 'AAPL', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'MSFT', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'GOOGL', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'AMZN', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'NVDA', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'META', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'TSLA', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'BRK-B', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'JPM', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'V', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'JNJ', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'WMT', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'PG', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'MA', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'HD', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'XOM', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'BAC', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'KO', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'PEP', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'COST', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'AVGO', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'NFLX', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'AMD', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'INTC', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'CRM', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'ORCL', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'ADBE', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'DIS', kind: MarketAssetKind.stocks),
  // Stocks — Europe (Yahoo suffixes)
  WatchlistEntry(symbol: 'SAP.DE', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'SIE.DE', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'AIR.PA', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'MC.PA', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'ASML.AS', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'NESN.SW', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'SHEL.L', kind: MarketAssetKind.stocks),
  WatchlistEntry(symbol: 'AZN.L', kind: MarketAssetKind.stocks),
];

/// Flat symbol list derived from [defaultWatchlistEntries].
final defaultWatchlist =
    defaultWatchlistEntries.map((e) => e.symbol).toList(growable: false);

/// Markets tab subgroups (crypto lives on the Crypto tab).
const marketTabKinds = <MarketAssetKind>[
  MarketAssetKind.indices,
  MarketAssetKind.etfs,
  MarketAssetKind.stocks,
];

/// Lookup of curated asset kind by Yahoo symbol.
final Map<String, MarketAssetKind> watchlistKindBySymbol = {
  for (final entry in defaultWatchlistEntries) entry.symbol: entry.kind,
};

/// Curated symbols for one Markets subgroup.
List<String> watchlistSymbolsForKind(MarketAssetKind kind) {
  return defaultWatchlistEntries
      .where((e) => e.kind == kind)
      .map((e) => e.symbol)
      .toList(growable: false);
}

/// Quotes under one exchange within an asset group.
class MarketExchangeGroup {
  const MarketExchangeGroup({
    required this.exchange,
    required this.quotes,
  });

  final String exchange;
  final List<Quote> quotes;
}

/// Asset-kind group with exchange subgroups.
class MarketKindGroup {
  const MarketKindGroup({
    required this.kind,
    required this.exchanges,
  });

  final MarketAssetKind kind;
  final List<MarketExchangeGroup> exchanges;

  String get label => kind.label;

  int get quoteCount =>
      exchanges.fold(0, (sum, group) => sum + group.quotes.length);
}

/// Friendly label for Yahoo exchange strings (falls back to raw / Other).
String displayExchangeName(String? exchange) {
  final raw = exchange?.trim();
  if (raw == null || raw.isEmpty) return 'Other';

  return switch (raw) {
    'SNP' || 'SP' => 'S&P',
    'DJI' => 'Dow Jones',
    'NMS' || 'NasdaqGS' || 'NASDAQ' => 'Nasdaq',
    'NYQ' || 'NYSE' => 'NYSE',
    'NYSEArca' || 'PCX' || 'ARCA' => 'NYSE Arca',
    'NIM' || 'Nasdaq GIDS' || 'GI' => 'Nasdaq Indices',
    'XETRA' || 'GER' => 'Xetra',
    'CCC' => 'Crypto',
    _ => raw,
  };
}

/// Short plain-language note for a [displayExchangeName] label.
///
/// Used next to exchange headers in Markets so acronyms like NYSE / Nasdaq
/// are not a dead end for learners. Returns null when we have no blurb.
String? exchangeDescription(String displayName) {
  return switch (displayName) {
    'NYSE' =>
      'New York Stock Exchange — major U.S. listed company stocks.',
    'Nasdaq' =>
      'U.S. electronic exchange — many tech and growth stocks.',
    'NYSE Arca' =>
      'Lists many ETFs and other exchange-traded products.',
    'Nasdaq Indices' =>
      'Benchmark indexes tracked on Nasdaq.',
    'S&P' =>
      'Standard & Poor’s — publisher of widely followed market indexes.',
    'Dow Jones' =>
      'Publisher of the Dow Jones Industrial Average and related indexes.',
    'Xetra' =>
      'German electronic exchange for stocks and ETFs (Frankfurt).',
    'Crypto' =>
      'Digital-asset trading venues — not a traditional stock exchange.',
    'Other' =>
      'Listings without a known exchange label.',
    _ => null,
  };
}

/// Groups quotes by curated asset kind, then by exchange.
///
/// Kind order follows [MarketAssetKind] declaration. Empty kinds are omitted.
/// Unknown symbols (not in the curated map) are skipped.
List<MarketKindGroup> groupQuotesByKindAndExchange(List<Quote> quotes) {
  final byKind = <MarketAssetKind, Map<String, List<Quote>>>{};

  for (final quote in quotes) {
    final kind = watchlistKindBySymbol[quote.symbol];
    if (kind == null) continue;
    final exchange = displayExchangeName(quote.exchange);
    final exchanges = byKind.putIfAbsent(kind, () => {});
    exchanges.putIfAbsent(exchange, () => []).add(quote);
  }

  final groups = <MarketKindGroup>[];
  for (final kind in MarketAssetKind.values) {
    final exchanges = byKind[kind];
    if (exchanges == null || exchanges.isEmpty) continue;

    final exchangeNames = exchanges.keys.toList()..sort();
    groups.add(
      MarketKindGroup(
        kind: kind,
        exchanges: [
          for (final name in exchangeNames)
            MarketExchangeGroup(
              exchange: name,
              quotes: List<Quote>.unmodifiable(exchanges[name]!),
            ),
        ],
      ),
    );
  }
  return groups;
}
