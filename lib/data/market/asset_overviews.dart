/// Short plain-language overview for curated default symbols.
///
/// Returns null when no blurb is maintained for [symbol].
String? assetOverview(String symbol) {
  final key = symbol.trim().toUpperCase();
  if (key.isEmpty) return null;
  return _overviews[key];
}

const _overviews = <String, String>{
  // Indices
  '^GSPC':
      'The S&P 500 tracks 500 large U.S. companies — a common snapshot of '
          'the overall U.S. stock market.',
  '^DJI':
      'The Dow Jones Industrial Average follows 30 large, well-known U.S. '
          'companies across major industries.',
  '^IXIC':
      'The Nasdaq Composite covers thousands of stocks listed on Nasdaq, '
          'with a strong tilt toward technology companies.',

  // ETFs
  'SPY':
      'An ETF designed to track the S&P 500, so one share roughly mirrors '
          'that broad U.S. market index.',
  'QQQ':
      'An ETF that tracks the Nasdaq-100 — mostly large non-financial '
          'companies listed on Nasdaq, heavy on tech.',

  // Stocks
  'AAPL':
      'Apple designs and sells consumer electronics, software, and services '
          '(iPhone, Mac, and related apps).',
  'MSFT':
      'Microsoft builds software, cloud services, and devices — from Windows '
          'and Office to Azure.',
  'SAP.DE':
      'SAP is a German software company known for business applications that '
          'help large organizations run operations.',

  // Crypto (Crypto.com default pairs)
  'BTC_USD':
      'Bitcoin is the largest cryptocurrency by market value — a digital '
          'asset that can be sent peer-to-peer without a bank.',
  'ETH_USD':
      'Ethereum is a major cryptocurrency and the network behind many '
          'apps, tokens, and smart contracts.',
  'SOL_USD':
      'Solana is a cryptocurrency and blockchain built for fast, low-cost '
          'transactions and apps.',
  'XRP_USD':
      'XRP is the token used on the XRP Ledger, often associated with '
          'cross-border payment experiments.',
  'ADA_USD':
      'Cardano (ADA) is a cryptocurrency and blockchain focused on '
          'peer-reviewed research and energy-efficient validation.',
  'DOGE_USD':
      'Dogecoin started as a lighthearted meme coin and is still traded '
          'widely as a cryptocurrency.',
};
