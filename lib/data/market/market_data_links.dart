/// Label + URI for an external research / attribution page.
class ExternalMarketLink {
  const ExternalMarketLink({required this.label, required this.uri});

  final String label;
  final Uri uri;
}

/// Public web pages for live market-data providers (attribution / deep links).
Uri? publicMarketPageUrl({
  required String symbol,
  String? dataSourceId,
}) {
  final id = dataSourceId?.trim();
  final sym = symbol.trim();
  if (id == null || id.isEmpty || sym.isEmpty) return null;

  return switch (id) {
    // Encode the symbol ourselves — Uri.https would turn `%` into `%25`.
    'yahoo' => Uri.parse(
        'https://finance.yahoo.com/quote/${Uri.encodeComponent(sym)}',
      ),
    'crypto_com' => Uri.https(
        'crypto.com',
        '/exchange/trade/$sym',
      ),
    _ => null,
  };
}

String? _providerDisplayName(String? dataSourceId) {
  return switch (dataSourceId?.trim()) {
    'yahoo' => 'Yahoo Finance',
    'crypto_com' => 'Crypto.com',
    _ => null,
  };
}

/// Research / attribution links for the asset detail screen.
///
/// Order: provider page (when known), Wikipedia (when mapped), Google Finance,
/// TradingView.
List<ExternalMarketLink> externalMarketLinks({
  required String symbol,
  String? dataSourceId,
  String? exchange,
}) {
  final sym = symbol.trim();
  if (sym.isEmpty) return const [];

  final links = <ExternalMarketLink>[];

  final providerUri = publicMarketPageUrl(
    symbol: sym,
    dataSourceId: dataSourceId,
  );
  final providerName = _providerDisplayName(dataSourceId);
  if (providerUri != null && providerName != null) {
    links.add(
      ExternalMarketLink(label: 'View on $providerName', uri: providerUri),
    );
  }

  final wiki = wikipediaUrl(symbol: sym);
  if (wiki != null) {
    links.add(ExternalMarketLink(label: 'Wikipedia', uri: wiki));
  }

  links.add(
    ExternalMarketLink(
      label: 'Google Finance',
      uri: googleFinanceUrl(symbol: sym, exchange: exchange),
    ),
  );
  links.add(
    ExternalMarketLink(
      label: 'TradingView',
      uri: tradingViewUrl(symbol: sym, exchange: exchange),
    ),
  );

  return links;
}

/// Wikipedia article for a curated symbol, or null when unmapped.
Uri? wikipediaUrl({required String symbol}) {
  final key = symbol.trim().toUpperCase();
  if (key.isEmpty) return null;
  final title = _wikipediaTitles[key];
  if (title == null || title.isEmpty) return null;
  // Keep `_`, `.`, and `()` literal; only `&` needs percent-encoding.
  return Uri.parse(
    'https://en.wikipedia.org/wiki/${title.replaceAll('&', '%26')}',
  );
}

/// Google Finance quote URL, or search fallback when mapping is unknown.
Uri googleFinanceUrl({required String symbol, String? exchange}) {
  final sym = symbol.trim();
  final quotePath = _googleFinanceQuotePath(sym, exchange);
  if (quotePath != null) {
    // Keep `:`, `.`, `-` literal — encodeComponent would break Google's path form.
    return Uri.parse('https://www.google.com/finance/quote/$quotePath');
  }
  return Uri.https('www.google.com', '/finance/search', {'q': sym});
}

/// TradingView chart deep link with a best-effort symbol.
Uri tradingViewUrl({required String symbol, String? exchange}) {
  final tv = _tradingViewSymbol(symbol.trim(), exchange);
  return Uri.https('www.tradingview.com', '/chart/', {'symbol': tv});
}

String? _googleFinanceQuotePath(String symbol, String? exchange) {
  final index = _googleIndexPath[symbol];
  if (index != null) return index;

  final crypto = _cryptoPairParts(symbol);
  if (crypto != null) return '${crypto.$1}-${crypto.$2}';

  final yahooSuffix = _yahooSuffixTicker(symbol);
  if (yahooSuffix != null) {
    final googleEx = _yahooSuffixToGoogleExchange[yahooSuffix.$2];
    if (googleEx != null) return '${yahooSuffix.$1}:$googleEx';
  }

  final googleEx = _yahooExchangeToGoogle(exchange);
  if (googleEx != null) return '$symbol:$googleEx';

  // Plain US-style tickers without exchange still resolve on Google often.
  if (_looksLikePlainTicker(symbol)) return symbol;

  return null;
}

String _tradingViewSymbol(String symbol, String? exchange) {
  final index = _tradingViewIndexSymbol[symbol];
  if (index != null) return index;

  final crypto = _cryptoPairParts(symbol);
  if (crypto != null) return 'CRYPTO:${crypto.$1}${crypto.$2}';

  final yahooSuffix = _yahooSuffixTicker(symbol);
  if (yahooSuffix != null) {
    final tvEx = _yahooSuffixToTradingViewExchange[yahooSuffix.$2];
    if (tvEx != null) return '$tvEx:${yahooSuffix.$1}';
  }

  final tvEx = _yahooExchangeToTradingView(exchange);
  if (tvEx != null) return '$tvEx:$symbol';

  if (symbol.contains('_')) return symbol.replaceAll('_', '');
  if (symbol.contains('-')) return symbol.replaceAll('-', '');
  return symbol;
}

(String, String)? _cryptoPairParts(String symbol) {
  final match = RegExp(r'^([A-Z0-9]+)_([A-Z0-9]+)$').firstMatch(symbol);
  if (match == null) return null;
  return (match.group(1)!, match.group(2)!);
}

(String, String)? _yahooSuffixTicker(String symbol) {
  final match = RegExp(r'^([A-Z0-9]+)\.([A-Z]+)$').firstMatch(symbol);
  if (match == null) return null;
  return (match.group(1)!, match.group(2)!);
}

bool _looksLikePlainTicker(String symbol) {
  return RegExp(r'^[A-Z]{1,5}$').hasMatch(symbol);
}

String? _yahooExchangeToGoogle(String? exchange) {
  final raw = exchange?.trim();
  if (raw == null || raw.isEmpty) return null;
  return switch (raw) {
    'NMS' || 'NasdaqGS' || 'NASDAQ' => 'NASDAQ',
    'NYQ' || 'NYSE' => 'NYSE',
    'NYSEArca' || 'PCX' || 'ARCA' => 'NYSEARCA',
    'GER' || 'XETRA' => 'ETR',
    _ => null,
  };
}

String? _yahooExchangeToTradingView(String? exchange) {
  final raw = exchange?.trim();
  if (raw == null || raw.isEmpty) return null;
  return switch (raw) {
    'NMS' || 'NasdaqGS' || 'NASDAQ' => 'NASDAQ',
    'NYQ' || 'NYSE' => 'NYSE',
    'NYSEArca' || 'PCX' || 'ARCA' => 'AMEX',
    'GER' || 'XETRA' => 'XETR',
    _ => null,
  };
}

/// Curated Wikipedia article titles for default watchlist / crypto pairs.
///
/// Unencoded page titles; [wikipediaUrl] percent-encodes the path segment.
const _wikipediaTitles = <String, String>{
  '^GSPC': 'S&P_500',
  '^DJI': 'Dow_Jones_Industrial_Average',
  '^IXIC': 'Nasdaq_Composite',
  'SPY': 'SPDR_S&P_500_Trust_Series_I',
  'QQQ': 'Invesco_QQQ',
  'AAPL': 'Apple_Inc.',
  'MSFT': 'Microsoft',
  'SAP.DE': 'SAP',
  'BTC_USD': 'Bitcoin',
  'ETH_USD': 'Ethereum',
  'SOL_USD': 'Solana_(blockchain_platform)',
  'XRP_USD': 'XRP_(cryptocurrency)',
  'ADA_USD': 'Cardano_(blockchain_platform)',
  'DOGE_USD': 'Dogecoin',
};

const _googleIndexPath = <String, String>{
  '^GSPC': '.INX:INDEXSP',
  '^DJI': '.DJI:INDEXDJX',
  '^IXIC': '.IXIC:INDEXNASDAQ',
};

const _tradingViewIndexSymbol = <String, String>{
  '^GSPC': 'SP:SPX',
  '^DJI': 'DJ:DJI',
  '^IXIC': 'NASDAQ:IXIC',
};

const _yahooSuffixToGoogleExchange = <String, String>{
  'DE': 'ETR',
};

const _yahooSuffixToTradingViewExchange = <String, String>{
  'DE': 'XETR',
};
