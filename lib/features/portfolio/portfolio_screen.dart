import '../../core/material_compat.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/brand_colors.dart';
import '../../core/fade_page_route.dart';
import '../../core/formatting.dart';
import '../../core/shell_navigation.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/crypto/exchange_portfolio.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/portfolio/models.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/portfolio/portfolio_repository.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/settings/settings_listen_keys.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_progress.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/metric_stat.dart';
import '../../widgets/summary_well.dart';
import '../../widgets/tab_page_header.dart';
import '../../widgets/tappable_nav_row.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../settings/portfolio_actions.dart';
import 'portfolio_screen_controller.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  static const wideBreakpoint = MasterDetailShell.wideBreakpointDefault;

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

class _PortfolioView extends StatefulWidget {
  const _PortfolioView();

  @override
  State<_PortfolioView> createState() => _PortfolioViewState();
}

class _PortfolioViewState extends State<_PortfolioView> {
  String _selectedId = PortfolioDescriptor.practiceId;
  String? _narrowSelectedId;

  void _select(String id, {required bool wide}) {
    setState(() {
      _selectedId = id;
      if (!wide) {
        _narrowSelectedId = id;
      }
    });
  }

  void _backToNavList() {
    setState(() => _narrowSelectedId = null);
  }

  PortfolioDescriptor? _byId(List<PortfolioDescriptor> list, String? id) {
    if (id == null) return null;
    for (final d in list) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _confirmReset(BuildContext context) async {
    final controller = context.read<PortfolioScreenController>();
    final reset = await confirmAndResetPracticePortfolio(context);
    if (reset && context.mounted) {
      await controller.refreshQuotes();
    }
  }

  Widget _refreshTrailing(PortfolioScreenController controller) {
    if (controller.isRefreshing) {
      return const AppProgress(compact: true);
    }
    return ShadButton.ghost(
      size: ShadButtonSize.sm,
      onPressed: controller.refreshAll,
      child: const Text('Refresh'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );
    final portfolio = context.watch<PortfolioRepository>();
    final state = portfolio.state;
    // Rebuild when exchange credential readiness or source toggles change
    // so Live subgroups appear without listening to unrelated secret edits.
    context.select<EnvSecretsRepository, String>(exchangeCredsFingerprint);
    context.select<DataSourceSettings, String>(dataSourceFingerprint);
    final controller = context.watch<PortfolioScreenController>();
    controller.syncLiveClientsIfNeeded();

    final descriptors = controller.portfolios;
    final hasLive = controller.hasLive;
    final pendingLive =
        context.read<CryptoExchangeRegistry>().pendingLivePortfolioClients;

    final wideSelected = _byId(descriptors, _selectedId) ??
        (descriptors.isEmpty ? null : descriptors.first);
    final narrowSelected = _byId(descriptors, _narrowSelectedId);

    final holdingsValue = controller.holdingsValueFor(state);
    final paperTotal = controller.paperTotalFor(state);
    final unrealized = controller.unrealizedFor(state);

    return InTabBackEffect(
      onBack: _narrowSelectedId != null ? _backToNavList : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_narrowSelectedId == null)
            TabPageHeader(
              title: 'Portfolio',
              subtitle: hasLive
                  ? 'Practice paper trading, plus live balances from '
                      'connected exchanges.'
                  : 'Practice with fake money — no account required.',
            ),
          Expanded(
            child: wideSelected == null
                ? const SizedBox.shrink()
                : MasterDetailShell<PortfolioDescriptor>(
                    selected: wideSelected,
                    narrowSelected: narrowSelected,
                    onNarrowBack: _backToNavList,
                    sidebarBuilder: (context, highlighted, {required wide}) {
                      return MasterDetailNavList(
                        leading: [
                          if (pendingLive.isNotEmpty)
                            _ConnectLivePortfolioCard(pending: pendingLive),
                        ],
                        tiles: [
                          for (final desc in descriptors)
                            MasterDetailNavTile(
                              title: desc.displayName,
                              icon: desc.isPractice
                                  ? LucideIcons.wallet
                                  : LucideIcons.landmark,
                              badge: desc.isPractice
                                  ? const ShadBadge.secondary(
                                      child: Text('Paper'),
                                    )
                                  : const ShadBadge(
                                      child: Text('Live'),
                                    ),
                              meta: desc.isPractice
                                  ? formatDisplayMoney(
                                      paperTotal,
                                      priceFormat,
                                    )
                                  : formatDisplayMoney(
                                      controller
                                          .liveByExchange[desc.id]?.totalValue,
                                      priceFormat,
                                    ),
                              selected: highlighted?.id == desc.id,
                              onTap: () => _select(desc.id, wide: wide),
                            ),
                        ],
                      );
                    },
                    contentBuilder:
                        (context, desc, {required showBack, onBack}) {
                      if (desc.isPractice) {
                        return MasterDetailContentPane(
                          key: const ValueKey('portfolio-practice'),
                          title: desc.displayName,
                          subtitle: 'Fake money for learning — not real funds.',
                          showBack: showBack,
                          onBack: onBack,
                          backLabel: 'Portfolio',
                          trailing: _refreshTrailing(controller),
                          body: RefreshIndicator(
                            color: ShadTheme.of(context).colorScheme.primary,
                            backgroundColor:
                                ShadTheme.of(context).colorScheme.background,
                            onRefresh: controller.refreshAll,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              children: [
                                _PracticeBody(
                                  cash: state.cash,
                                  holdingsValue: holdingsValue,
                                  paperTotal: paperTotal,
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
                              ],
                            ),
                          ),
                        );
                      }

                      return MasterDetailContentPane(
                        key: ValueKey('portfolio-live-${desc.id}'),
                        title: desc.displayName,
                        subtitle:
                            'Read-only balances from your API credentials.',
                        showBack: showBack,
                        onBack: onBack,
                        backLabel: 'Portfolio',
                        trailing: _refreshTrailing(controller),
                        body: RefreshIndicator(
                          color: ShadTheme.of(context).colorScheme.primary,
                          backgroundColor:
                              ShadTheme.of(context).colorScheme.background,
                          onRefresh: controller.refreshAll,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              _LiveBody(
                                exchangeId: desc.id,
                                exchangeName: desc.displayName,
                                snapshot:
                                    controller.liveByExchange[desc.id],
                                error: controller.liveErrors[desc.id],
                                loading: controller.loadingLive &&
                                    !controller.liveByExchange
                                        .containsKey(desc.id) &&
                                    !controller.liveErrors
                                        .containsKey(desc.id),
                                onRetry: controller.refreshLivePortfolios,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Soft CTA when Live-capable venues still need API credentials.
class _ConnectLivePortfolioCard extends StatelessWidget {
  const _ConnectLivePortfolioCard({required this.pending});

  final List<CryptoExchangeClient> pending;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final names = pending.map((c) => c.exchange.displayName).toList();
    final venues = names.length == 1
        ? names.single
        : names.length == 2
            ? '${names[0]} or ${names[1]}'
            : '${names.take(names.length - 1).join(', ')}, or ${names.last}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppCopy.connectLivePortfolioTitle,
              style: theme.textTheme.large.copyWith(
                color: theme.colorScheme.secondaryForeground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${AppCopy.connectLivePortfolioBody} Supported now: $venues.',
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.secondaryForeground,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton(
                onPressed: () {
                  context.read<ShellNavigationController>().goToSettings(
                        sectionId: 'dataSources',
                      );
                },
                child: const Text(AppCopy.connectLivePortfolioCta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeBody extends StatelessWidget {
  const _PracticeBody({
    required this.cash,
    required this.holdingsValue,
    required this.paperTotal,
    required this.unrealized,
    required this.holdings,
    required this.quotes,
    required this.quoteError,
    required this.onReset,
    required this.onOpenHolding,
  });

  final double cash;
  final double holdingsValue;
  final double paperTotal;
  final double unrealized;
  final List<Holding> holdings;
  final Map<String, Quote> quotes;
  final String? quoteError;
  final VoidCallback onReset;
  final ValueChanged<String> onOpenHolding;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );

    return Column(
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
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const AgentLaunchButton(
                intent: AgentLaunchIntent.explainPortfolio,
                outline: true,
                label: 'Allocation',
              ),
              const AgentLaunchButton(
                intent: AgentLaunchIntent.paperReview,
                outline: true,
                label: 'Coach',
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onReset,
                child: const Text('Reset'),
              ),
            ],
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
              paperTotal: paperTotal,
              onTap: () => onOpenHolding(holdings[i].symbol),
            ),
          ],
      ],
    );
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.exchangeId,
    required this.exchangeName,
    required this.snapshot,
    required this.error,
    required this.loading,
    required this.onRetry,
  });

  final String exchangeId;
  final String exchangeName;
  final ExchangePortfolioSnapshot? snapshot;
  final String? error;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppProgress()),
      );
    }

    if (error != null && snapshot == null) {
      return Column(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SummaryWell(
          tone: SummaryWellTone.live,
          eyebrow: 'Live · $exchangeName',
          blurb:
              'Real exchange balances from your API credentials. '
              'Read-only in Omniscope.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AgentLaunchButton(
                exchangeId: exchangeId,
                intent: AgentLaunchIntent.explainLive,
                outline: true,
                label: 'Balances',
              ),
              AgentLaunchButton(
                exchangeId: exchangeId,
                intent: AgentLaunchIntent.explainPortfolio,
                outline: true,
                label: 'Allocation',
              ),
            ],
          ),
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
            _BalanceTile(
              exchangeId: exchangeId,
              balance: data.balances[i],
            ),
          ],
      ],
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({
    required this.holding,
    required this.quote,
    required this.paperTotal,
    required this.onTap,
  });

  final Holding holding;
  final Quote? quote;
  final double paperTotal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );
    final price = quote?.price ?? holding.avgCost;
    final value = holding.shares * price;
    final pnl = value - holding.costBasis;
    final pnlColor = pnl >= 0
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);
    final weight = paperTotal > 0 ? value / paperTotal : null;

    final identity = quote?.listSubtitle;
    final holdingMeta =
        '${formatShares(holding.shares)} shares · '
        'avg ${formatDisplayMoney(holding.avgCost, priceFormat)}'
        '${weight == null ? '' : ' · ${formatPercent(weight)}'}';

    return TappableNavRow(
      onTap: onTap,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(holding.symbol, style: theme.textTheme.large),
          if (identity != null) ...[
            const SizedBox(height: 2),
            Text(
              identity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ],
          const SizedBox(height: 2),
          Text(
            holdingMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgentLaunchButton(
            symbol: holding.symbol,
            intent: AgentLaunchIntent.tradeCheck,
            iconOnly: true,
            quantity: holding.shares,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDisplayMoney(value, priceFormat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.large,
                ),
                const SizedBox(height: 2),
                Text(
                  formatSignedMoney(pnl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.small.copyWith(color: pnlColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.exchangeId,
    required this.balance,
  });

  final String exchangeId;
  final ExchangeBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );
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
            AgentLaunchButton(
              exchangeId: exchangeId,
              symbol: balance.asset,
              intent: AgentLaunchIntent.explainLive,
              iconOnly: true,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDisplayMoney(balance.marketValue, priceFormat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.large,
                  ),
                  if (balance.available != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'avail ${formatShares(balance.available!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.muted,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
