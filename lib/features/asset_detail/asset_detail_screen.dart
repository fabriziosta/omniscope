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
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/display_settings.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/metric_stat.dart';
import '../../widgets/price_line_chart.dart';
import '../../widgets/subscreen_app_bar.dart';
import 'asset_detail_controller.dart';

class AssetDetailScreen extends StatelessWidget {
  const AssetDetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AssetDetailController(
        symbol: symbol,
        marketData: context.read<MarketDataClient>(),
        portfolio: context.read<PortfolioRepository>(),
        initialRange: context.read<DisplaySettings>().defaultChartRange,
      )..load(),
      child: _AssetDetailView(symbol: symbol),
    );
  }
}

class _AssetDetailView extends StatefulWidget {
  const _AssetDetailView({required this.symbol});

  final String symbol;

  @override
  State<_AssetDetailView> createState() => _AssetDetailViewState();
}

class _AssetDetailViewState extends State<_AssetDetailView> {
  final _sharesController = TextEditingController(text: '1');

  @override
  void dispose() {
    _sharesController.dispose();
    super.dispose();
  }

  Future<void> _trade({required bool buy}) async {
    final controller = context.read<AssetDetailController>();
    final result = await controller.trade(
      buy: buy,
      sharesText: _sharesController.text,
    );
    if (!mounted) return;
    if (result == null) {
      showAppToast(
        context,
        title: 'Invalid quantity',
        description: 'Enter a valid share quantity.',
        destructive: true,
      );
      return;
    }
    showAppToast(
      context,
      title: result.title,
      description: result.description,
      destructive: !result.success,
    );
  }

  Future<void> _openExternalUri(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showAppToast(
          context,
          title: 'Could not open link',
          description: 'Try again or open the page in a browser.',
          destructive: true,
        );
      }
    } catch (e, st) {
      debugPrint('Open external market page failed: $e\n$st');
      if (!mounted) return;
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
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    final controller = context.watch<AssetDetailController>();
    final quote = controller.quote;
    final portfolio = context.watch<PortfolioRepository>();
    final holding = portfolio.state.holdingFor(widget.symbol);
    final overview = assetOverview(widget.symbol);
    final researchLinks = quote == null
        ? const <ExternalMarketLink>[]
        : externalMarketLinks(
            symbol: quote.symbol,
            dataSourceId: quote.dataSourceId,
            exchange: quote.exchange,
          );

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubscreenAppBar(
              title: widget.symbol,
              endPadding: 16,
            ),
            if (controller.loading)
              const Expanded(child: Center(child: AppProgress()))
            else if (controller.hasError)
              Expanded(
                child: AppErrorView(
                  title: 'Could not load ${widget.symbol}',
                  message: AppCopy.checkConnection,
                  onRetry: controller.load,
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
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
                            if (_hasQuoteMeta(quote)) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (quote!.exchange != null &&
                                      quote.exchange!.trim().isNotEmpty)
                                    _MetaChip(
                                      label:
                                          displayExchangeName(quote.exchange),
                                    ),
                                  if (quote.currency != null &&
                                      quote.currency!.trim().isNotEmpty)
                                    _MetaChip(label: quote.currency!),
                                  if (quote.previousClose != null)
                                    _MetaChip(
                                      label:
                                          'Prev ${formatDisplayMoney(quote.previousClose, priceFormat)}',
                                    ),
                                  if (quote.dataSource != null &&
                                      quote.dataSource!.trim().isNotEmpty)
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
                            if (overview != null) ...[
                              const SizedBox(height: 12),
                              Text(overview, style: theme.textTheme.muted),
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
                                      onPressed: () =>
                                          _openExternalUri(link.uri),
                                      child: Text(link.label),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            for (var i = 0;
                                i < AssetDetailController.ranges.length;
                                i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              ShadButton.raw(
                                size: ShadButtonSize.sm,
                                variant: i == controller.rangeIndex
                                    ? ShadButtonVariant.primary
                                    : ShadButtonVariant.outline,
                                onPressed: () => controller.setRange(i),
                                child: Text(
                                  AssetDetailController.ranges[i].$1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ShadCard(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PriceLineChart(candles: controller.candles),
                              if (controller.candles.length >= 2) ...[
                                const SizedBox(height: 8),
                                _PeriodStats(
                                  candles: controller.candles,
                                  rangeLabel: controller.currentRange.$1,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: ShadCard(
                          title: const Row(
                            children: [
                              Flexible(
                                child: Text('Practice trade'),
                              ),
                              SizedBox(width: 8),
                              ShadBadge.secondary(
                                child: Text('Paper'),
                              ),
                            ],
                          ),
                          description: Text(
                            'Uses your practice portfolio cash '
                            '(${formatDisplayMoney(portfolio.state.cash, priceFormat)}). '
                            'Not a live order — no real money.',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 12),
                              ShadInput(
                                controller: _sharesController,
                                placeholder: const Text('Shares'),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ShadButton(
                                      onPressed: () => _trade(buy: true),
                                      child: const Text('Buy'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ShadButton.outline(
                                      onPressed: () => _trade(buy: false),
                                      child: const Text('Sell'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasQuoteMeta(Quote? quote) {
    if (quote == null) return false;
    return (quote.exchange != null && quote.exchange!.trim().isNotEmpty) ||
        (quote.currency != null && quote.currency!.trim().isNotEmpty) ||
        quote.previousClose != null ||
        (quote.dataSource != null && quote.dataSource!.trim().isNotEmpty);
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
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
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
