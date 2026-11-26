import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_copy.dart';
import '../../core/brand_colors.dart';
import '../../core/formatting.dart';
import '../../data/market/asset_overviews.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/market_data_links.dart';
import '../../data/market/models.dart';
import '../../data/portfolio/models.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/display_settings.dart';
import '../../data/agents/agent_launch.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_tooltip.dart';
import '../../widgets/delayed_data_caption.dart';
import '../../widgets/metric_stat.dart';
import '../../widgets/price_line_chart.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'asset_detail_controller.dart';

/// Venue-style spot pairs use an underscore (e.g. `BTC_USD`).
bool _isCryptoSpotSymbol(String symbol) => symbol.contains('_');

class AssetDetailScreen extends StatelessWidget {
  const AssetDetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AssetDetailController(
        symbol: symbol,
        marketData: context.read<MarketDataClient>(),
        initialRange: context.read<DisplaySettings>().defaultChartRange,
      )..load(),
      child: _AssetDetailView(symbol: symbol),
    );
  }
}

class _AssetDetailView extends StatelessWidget {
  const _AssetDetailView({required this.symbol});

  final String symbol;

  Future<void> _openExternalUri(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        showAppToast(
          context,
          title: 'Could not open link',
          description: 'Try again or open the page in a browser.',
          destructive: true,
        );
      }
    } catch (e, st) {
      debugPrint('Open external market page failed: $e\n$st');
      if (!context.mounted) return;
      showAppToast(
        context,
        title: 'Could not open link',
        description: 'Try again or open the page in a browser.',
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final loading = context.select<AssetDetailController, bool>(
      (c) => c.loading,
    );
    final hasError = context.select<AssetDetailController, bool>(
      (c) => c.hasError,
    );

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubscreenAppBar(
              title: symbol,
              endPadding: 8,
              trailing: AgentLaunchButton(
                symbol: symbol,
                intent: _isCryptoSpotSymbol(symbol)
                    ? AgentLaunchIntent.explainCryptoSpot
                    : AgentLaunchIntent.investigate,
              ),
            ),
            if (loading)
              const Expanded(child: Center(child: AppProgress()))
            else if (hasError)
              Expanded(
                child: _AssetDetailErrorBody(symbol: symbol),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AssetDetailQuoteHeader(
                        symbol: symbol,
                        onOpenExternalUri: _openExternalUri,
                      ),
                      const _AssetDetailChartSection(),
                      _AssetDetailTradeCard(symbol: symbol),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetDetailErrorBody extends StatelessWidget {
  const _AssetDetailErrorBody({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final message = context.select<AssetDetailController, String?>(
      (c) => c.loadErrorMessage,
    );
    final controller = context.read<AssetDetailController>();
    return AppErrorView(
      title: 'Could not load $symbol',
      message: message ?? 'Please try again in a moment.',
      onRetry: controller.load,
    );
  }
}

class _AssetDetailQuoteHeader extends StatelessWidget {
  const _AssetDetailQuoteHeader({
    required this.symbol,
    required this.onOpenExternalUri,
  });

  final String symbol;
  final Future<void> Function(BuildContext context, Uri uri) onOpenExternalUri;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (s) => s.priceFormat,
    );
    final quote = context.select<AssetDetailController, Quote?>(
      (c) => c.quote,
    );
    final fetchedAt = context.select<AssetDetailController, DateTime?>(
      (c) => c.fetchedAt,
    );
    final holding = context.select<PortfolioRepository, Holding?>(
      (p) => p.state.holdingFor(symbol),
    );
    final overview = assetOverview(symbol);
    final researchLinks = quote == null
        ? const <ExternalMarketLink>[]
        : externalMarketLinks(
            symbol: quote.symbol,
            dataSourceId: quote.dataSourceId,
            exchange: quote.exchange,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote?.name != null)
            Text(quote!.name!, style: theme.textTheme.muted),
          const SizedBox(height: 4),
          Text(
            formatDisplayMoney(quote?.price, priceFormat),
            style: theme.textTheme.h2,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatSignedMoney(quote?.change)}  '
            '${formatPercent(quote?.changePercent)}',
            style: theme.textTheme.small.copyWith(
              color: (quote?.isUp ?? true)
                  ? BrandColors.gainOf(context)
                  : BrandColors.lossOf(context),
            ),
          ),
          DelayedDataCaption(
            fetchedAt: fetchedAt,
            padding: const EdgeInsets.only(top: 10),
          ),
          if (assetDetailHasQuoteMeta(quote)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (quote!.exchange != null &&
                    quote.exchange!.trim().isNotEmpty)
                  _ExchangeMetaChip(
                    exchange: quote.exchange,
                  ),
                if (quote.currency != null &&
                    quote.currency!.trim().isNotEmpty)
                  _MetaChip(label: quote.currency!),
                if (quote.previousClose != null)
                  _MetaChip(
                    label:
                        'Prev ${formatDisplayMoney(quote.previousClose, priceFormat)}',
                  ),
                if (assetDetailShowDataSourceChip(quote))
                  _MetaChip(label: quote.dataSource!),
              ],
            ),
          ],
          if (holding != null) ...[
            const SizedBox(height: 8),
            Text(
              'You hold ${formatShares(holding.shares)} shares · '
              'avg ${formatDisplayMoney(holding.avgCost, priceFormat)}',
              style: theme.textTheme.muted,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            overview ??
                (_isCryptoSpotSymbol(symbol)
                    ? AppCopy.assetOverviewCryptoFallback
                    : AppCopy.assetOverviewFallback),
            style: theme.textTheme.muted,
          ),
          if (overview == null) ...[
            const SizedBox(height: 8),
            AgentLaunchButton(
              symbol: symbol,
              intent: _isCryptoSpotSymbol(symbol)
                  ? AgentLaunchIntent.explainCryptoSpot
                  : AgentLaunchIntent.explainMarketsLiteracy,
              outline: true,
              showTradeOption: false,
            ),
          ],
          if (researchLinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                for (final link in researchLinks)
                  ShadButton.link(
                    size: ShadButtonSize.sm,
                    onPressed: () => onOpenExternalUri(context, link.uri),
                    child: Text(link.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetDetailChartSection extends StatelessWidget {
  const _AssetDetailChartSection();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final candles = context.select<AssetDetailController, List<Candle>>(
      (c) => c.candles,
    );
    final rangeIndex = context.select<AssetDetailController, int>(
      (c) => c.rangeIndex,
    );
    final rangeLabel = AssetDetailController.ranges[rangeIndex].$1;
    final controller = context.read<AssetDetailController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              for (var i = 0; i < AssetDetailController.ranges.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                AppTooltip(
                  message: AssetDetailController.rangeTooltip(
                    AssetDetailController.ranges[i].$1,
                  ),
                  child: ShadButton.raw(
                    size: ShadButtonSize.sm,
                    variant: i == rangeIndex
                        ? ShadButtonVariant.primary
                        : ShadButtonVariant.outline,
                    onPressed: () => controller.setRange(i),
                    child: Text(
                      AssetDetailController.ranges[i].$1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            AssetDetailController.rangeExplainer(rangeLabel),
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ShadCard(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PriceLineChart(candles: candles),
                if (candles.length >= 2) ...[
                  const SizedBox(height: 8),
                  _PeriodStats(
                    candles: candles,
                    rangeLabel: rangeLabel,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AssetDetailTradeCard extends StatelessWidget {
  const _AssetDetailTradeCard({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (s) => s.priceFormat,
    );
    final cash = context.select<PortfolioRepository, double>(
      (p) => p.state.cash,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ShadCard(
        title: const Text('Trade with agents'),
        description: Text(
          'Buys and sells come from agent suggestions. '
          'Ask for a Trade check, then Confirm or Dismiss in '
          'chat — or turn on Autopilot. Practice cash: '
          '${formatDisplayMoney(cash, priceFormat)}.',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AgentLaunchButton(
                  symbol: symbol,
                  intent: AgentLaunchIntent.explainPortfolio,
                  outline: true,
                ),
                AgentLaunchButton(
                  symbol: symbol,
                  intent: AgentLaunchIntent.tradeCheck,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool assetDetailHasQuoteMeta(Quote? quote) {
  if (quote == null) return false;
  return (quote.exchange != null && quote.exchange!.trim().isNotEmpty) ||
      (quote.currency != null && quote.currency!.trim().isNotEmpty) ||
      quote.previousClose != null ||
      assetDetailShowDataSourceChip(quote);
}

/// Crypto venues set [Quote.exchange] and [Quote.dataSource] to the same
/// display name (e.g. both "Crypto.com"); skip the second pill.
bool assetDetailShowDataSourceChip(Quote quote) {
  final source = quote.dataSource?.trim();
  if (source == null || source.isEmpty) return false;
  final exchange = quote.exchange?.trim();
  if (exchange == null || exchange.isEmpty) return true;
  final sourceKey = source.toLowerCase();
  return sourceKey != exchange.toLowerCase() &&
      sourceKey != displayExchangeName(exchange).toLowerCase();
}

class _ExchangeMetaChip extends StatelessWidget {
  const _ExchangeMetaChip({required this.exchange});

  final String? exchange;

  @override
  Widget build(BuildContext context) {
    final name = displayExchangeName(exchange);
    final blurb = exchangeDescription(name);
    final chip = _MetaChip(label: name);
    if (blurb == null) return chip;
    return AppTooltip(
      message: blurb,
      wrapDetector: true,
      child: chip,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Text(
        label,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.secondaryForeground,
        ),
      ),
    );
  }
}

class _PeriodStats extends StatelessWidget {
  const _PeriodStats({
    required this.candles,
    required this.rangeLabel,
  });

  final List<Candle> candles;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (s) => s.priceFormat,
    );
    final first = candles.first.close;
    final last = candles.last.close;
    final change = last - first;
    final changePercent = first == 0 ? null : change / first;
    final up = change >= 0;

    var high = candles.first.close;
    var low = candles.first.close;
    for (final c in candles) {
      final hi = c.high ?? c.close;
      final lo = c.low ?? c.close;
      if (hi > high) high = hi;
      if (lo < low) low = lo;
    }
    final volume = candles.last.volume;

    final changeColor =
        up ? BrandColors.gainOf(context) : BrandColors.lossOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$rangeLabel range',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              MetricStat(
                label: 'Change',
                value: '${formatSignedMoney(change)}  '
                    '${formatPercent(changePercent)}',
                valueColor: changeColor,
              ),
              MetricStat(
                label: 'High',
                value: formatDisplayMoney(high, priceFormat),
              ),
              MetricStat(
                label: 'Low',
                value: formatDisplayMoney(low, priceFormat),
              ),
              if (volume != null)
                MetricStat(
                  label: 'Volume',
                  value: formatCompactNumber(volume),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
