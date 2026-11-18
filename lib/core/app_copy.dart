/// Shared product copy used across surfaces.
abstract final class AppCopy {
  static const tagline = 'My trusted learning and trading buddy';

  /// Bottom-nav hover / long-press hints (plain language, not just the label).
  static const tabTooltipMarkets =
      'Browse favorites, equities, and spot crypto by exchange';
  static const tabTooltipPortfolio =
      'Practice paper trading and live exchange balances';
  static const tabTooltipActivity =
      'Confirm pending agent suggestions and review past operations';
  static const tabTooltipAgents =
      'Connect AI helpers and open chat';
  static const tabTooltipSettings =
      'Appearance, data sources, and on-device preferences';

  static const checkConnection = 'Check your connection, then try again.';

  static const webMarketDataHint =
      'Market data on Web can be blocked by the browser or CORS proxy. '
      'Try again, or use the desktop or mobile app.';

  static const couldNotLoadMoreQuotes =
      'Could not load more quotes. Try again.';

  static const couldNotLoadQuotes = 'Could not load quotes';

  static const delayedDataCaption =
      'Prices may be delayed — educational use only.';

  static const assetOverviewFallback =
      'No short overview for this symbol yet. Use Investigate for a '
      'plain-language research turn, or open the research links below.';

  static const filterQuotesHint = 'Filter by symbol…';

  static const symbolSearchHint = 'Search symbols or names…';

  static const symbolSearchEmpty =
      'Type part of a symbol or name to find assets in Omniscope.';

  static const symbolSearchNoMatches = 'No symbols match that search.';

  static const symbolSearchTooltip = 'Search symbols';

  static const noQuotesMatchFilter = 'No quotes match that filter.';

  static const noQuotes = 'No quotes available';

  static const noMarketFavorites =
      'No favorites yet. Star a symbol from Indices, ETFs, Stocks, or '
      'any spot exchange list.';

  static const noInvestInterest =
      'No invest-interest symbols yet. Tap the target icon on a quote to '
      'mark assets you want agents to focus on, or let investigation agents '
      'add symbols (Confirm, or Autopilot for adds only).';

  static const investInterestManagedByAgent =
      'Agent recently updated this list. Rows are labeled You or Agent by '
      'who added each symbol. Manual edits clear the managed badge.';

  static const mandateIntro =
      'Set your investing policy once. Connected agents read this mandate '
      'and may propose Invest interest changes. With Autopilot off, you '
      'Confirm every change; with Autopilot on, investigation agents may '
      'auto-add symbols (remove/set still need Confirm).';

  static const mandateRiskRailsSaved =
      'Agents will respect these caps on Confirm and Autopilot.';

  static const noMarketSourcesEnabled =
      'No market data sources enabled. Turn one on in Settings.';

  static const noCryptoExchangesEnabled =
      'No crypto exchanges enabled. Turn one on in Settings.';

  static const noCryptoExchangesRegistered = 'No crypto exchanges registered';

  static const portfolioQuoteError = 'Could not refresh prices. Try again.';

  /// Portfolio tab CTA when a live-capable exchange has no API credentials yet.
  static const connectLivePortfolioTitle = 'Unlock live balances';

  static const connectLivePortfolioBody =
      'Practice is paper money only. Add an exchange API key and secret under '
      'Data sources to unlock read-only Live balances here.';

  static const connectLivePortfolioCta = 'Open Data sources';
}
