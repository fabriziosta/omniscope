import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/formatting.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/crypto/exchange_portfolio.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/portfolio/models.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/metric_stat.dart';
import '../../widgets/summary_well.dart';
import '../../widgets/tappable_nav_row.dart';
import '../../widgets/themed_accordion_item.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../settings/portfolio_actions.dart';
import 'portfolio_screen_controller.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PortfolioScreenController(
        marketData: context.read<MarketDataClient>(),
        portfolio: context.read<PortfolioRepository>(),
        cryptoRegistry: context.read<CryptoExchangeRegistry>(),
        dataSources: context.read<DataSourceSettings>(),
      )..refreshAll(),
      child: const _PortfolioView(),
    );
  }
}

class _PortfolioView extends StatelessWidget {
  const _PortfolioView();

  Future<void> _confirmReset(BuildContext context) async {
    final controller = context.read<PortfolioScreenController>();
    final reset = await confirmAndResetPracticePortfolio(context);
    if (reset && context.mounted) {
      await controller.refreshQuotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    final portfolio = context.watch<PortfolioRepository>();
    final state = portfolio.state;
    // Rebuild when credentials change so Live subgroups appear immediately.
    context.watch<EnvSecretsRepository>();
    context.watch<DataSourceSettings>();
    context.watch<CryptoExchangeRegistry>();
    final controller = context.watch<PortfolioScreenController>();
    controller.syncLiveClientsIfNeeded();

    final descriptors = controller.portfolios;
    final hasLive = controller.hasLive;

    final holdingsValue = controller.holdingsValueFor(state);
    final paperTotal = controller.paperTotalFor(state);
    final unrealized = controller.unrealizedFor(state);

    final accordionValues = <Object>[
      for (final d in descriptors) d.id,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Portfolio', style: theme.textTheme.h3),
                    const SizedBox(height: 4),
                    Text(
                      hasLive
                          ? 'Practice paper trading, plus live balances from '
                              'connected exchanges.'
                          : 'Practice with fake money — no account required.',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
              if (controller.isRefreshing)
                const AppProgress(compact: true)
              else
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: controller.refreshAll,
                  child: const Text('Refresh'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              ShadAccordion<Object>.multiple(
                initialValue: accordionValues,
                children: [
                  for (final desc in descriptors)
                    if (desc.isPractice)
                      ThemedAccordionItem<Object>(
                        value: desc.id,
                        title: _SectionTitle(
                          name: desc.displayName,
                          subtitle: formatDisplayMoney(paperTotal, priceFormat),
                          badge: const ShadBadge.secondary(
                            child: Text('Paper'),
                          ),
                        ),
                        child: _PracticeBody(
                          cash: state.cash,
                          holdingsValue: holdingsValue,
                          unrealized: unrealized,
                          holdings: state.holdings,
                          quotes: controller.quotes,
                          quoteError: controller.quoteError,
                          onReset: () => _confirmReset(context),
                          onOpenHolding: (symbol) {
                            pushFadePage(
                              context,
                              AssetDetailScreen(symbol: symbol),
                            ).then((_) {
                              if (context.mounted) {
                                controller.refreshQuotes();
                              }
                            });
                          },
                        ),
                      )
                    else
                      ThemedAccordionItem<Object>(
                        value: desc.id,
                        title: _SectionTitle(
                          name: desc.displayName,
                          subtitle: formatDisplayMoney(
                            controller.liveByExchange[desc.id]?.totalValue,
                            priceFormat,
                          ),
                          badge: const ShadBadge(
                            child: Text('Live'),
                          ),
                        ),
                        child: _LiveBody(
                          exchangeName: desc.displayName,
                          snapshot: controller.liveByExchange[desc.id],
                          error: controller.liveErrors[desc.id],
                          loading: controller.loadingLive &&
                              !controller.liveByExchange.containsKey(desc.id) &&
                              !controller.liveErrors.containsKey(desc.id),
                          onRetry: controller.refreshLivePortfolios,
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.name,
    required this.subtitle,
    required this.badge,
  });

  final String name;
  final String subtitle;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            style: theme.textTheme.large,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        badge,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            subtitle,
            style: theme.textTheme.muted,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _PracticeBody extends StatelessWidget {
  const _PracticeBody({
    required this.cash,
    required this.holdingsValue,
    required this.unrealized,
    required this.holdings,
    required this.quotes,
    required this.quoteError,
    required this.onReset,
    required this.onOpenHolding,
  });

  final double cash;
  final double holdingsValue;
  final double unrealized;
  final List<Holding> holdings;
  final Map<String, Quote> quotes;
  final String? quoteError;
  final VoidCallback onReset;
  final ValueChanged<String> onOpenHolding;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryWell(
            tone: SummaryWellTone.paper,
            eyebrow: 'Practice portfolio',
            blurb: 'Fake money for learning — not real funds.',
            totalLabel: 'Total value',
            totalValue: formatDisplayMoney(
              cash + holdingsValue,
              priceFormat,
            ),
            trailing: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onReset,
              child: const Text('Reset'),
            ),
            stats: [
              MetricStat(
                label: 'Cash',
                value: formatDisplayMoney(cash, priceFormat),
              ),
              MetricStat(
                label: 'Holdings',
                value: formatDisplayMoney(holdingsValue, priceFormat),
              ),
              MetricStat(
                label: 'Unrealized P&L',
                value: formatSignedMoney(unrealized),
                valueColor: unrealized >= 0
                    ? BrandColors.gainOf(context)
                    : BrandColors.lossOf(context),
              ),
            ],
          ),
          if (quoteError != null) ...[
            const SizedBox(height: 10),
            Text(
              quoteError!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Holdings', style: theme.textTheme.large),
          const SizedBox(height: 8),
          if (holdings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No holdings yet.\nBuy something from Markets.',
                textAlign: TextAlign.center,
                style: theme.textTheme.muted,
              ),
            )
          else
            for (var i = 0; i < holdings.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _HoldingTile(
                holding: holdings[i],
                quote: quotes[holdings[i].symbol],
                onTap: () => onOpenHolding(holdings[i].symbol),
              ),
            ],
        ],
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.exchangeName,
    required this.snapshot,
    required this.error,
    required this.loading,
    required this.onRetry,
  });

  final String exchangeName;
  final ExchangePortfolioSnapshot? snapshot;
  final String? error;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppProgress()),
      );
    }

    if (error != null && snapshot == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error!,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
            const SizedBox(height: 8),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final data = snapshot;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No live data yet.',
          style: theme.textTheme.muted,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryWell(
            tone: SummaryWellTone.live,
            eyebrow: 'Live · $exchangeName',
            blurb:
                'Real exchange balances from your API credentials. '
                'Read-only in Omniscope.',
            totalLabel: 'Total cash balance',
            totalValue: formatDisplayMoney(data.totalValue, priceFormat),
            stats: [
              MetricStat(
                label: 'Available',
                value: formatDisplayMoney(data.availableValue, priceFormat),
              ),
              MetricStat(
                label: 'Assets',
                value: '${data.balances.length}',
              ),
              MetricStat(
                label: 'Currency',
                value: data.currency,
              ),
            ],
            footer: error == null
                ? null
                : Text(
                    error!,
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.destructive,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text('Balances', style: theme.textTheme.large),
          const SizedBox(height: 8),
          if (data.balances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No non-zero balances on this exchange.',
                textAlign: TextAlign.center,
                style: theme.textTheme.muted,
              ),
            )
          else
            for (var i = 0; i < data.balances.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _BalanceTile(balance: data.balances[i]),
            ],
        ],
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({
    required this.holding,
    required this.quote,
    required this.onTap,
  });

  final Holding holding;
  final Quote? quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    final price = quote?.price ?? holding.avgCost;
    final value = holding.shares * price;
    final pnl = value - holding.costBasis;
    final pnlColor = pnl >= 0
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);

    return TappableNavRow(
      onTap: onTap,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(holding.symbol, style: theme.textTheme.large),
          const SizedBox(height: 2),
          Text(
            '${formatShares(holding.shares)} shares · '
            'avg ${formatDisplayMoney(holding.avgCost, priceFormat)}',
            style: theme.textTheme.muted,
          ),
        ],
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatDisplayMoney(value, priceFormat),
            style: theme.textTheme.large,
          ),
          const SizedBox(height: 2),
          Text(
            formatSignedMoney(pnl),
            style: theme.textTheme.small.copyWith(color: pnlColor),
          ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance});

  final ExchangeBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(balance.asset, style: theme.textTheme.large),
                  const SizedBox(height: 2),
                  Text(
                    '${formatShares(balance.quantity)} units',
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDisplayMoney(balance.marketValue, priceFormat),
                  style: theme.textTheme.large,
                ),
                if (balance.available != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'avail ${formatShares(balance.available!)}',
                    style: theme.textTheme.muted,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
