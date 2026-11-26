import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../../widgets/quotes_load_more_bar.dart';
import '../../widgets/quotes_paging_error_listener.dart';
import '../../widgets/section_caption.dart';
import '../../widgets/symbol_search.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Markets subgroup content pane: header chrome + quote list for [kind].
///
/// Remount with a [ValueKey] on [kind] when the sidebar selection changes.
class MarketKindPane extends StatelessWidget {
  const MarketKindPane({
    super.key,
    required this.kind,
    required this.onOpenMenu,
  });

  final MarketAssetKind kind;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final symbols = watchlistSymbolsForKind(kind);
    return ChangeNotifierProvider(
      create: (context) => QuotesListController(
        client: context.read<MarketDataClient>(),
        symbols: symbols,
        errorTitle: 'Could not load ${kind.label}',
      )..refresh(),
      child: _MarketKindPaneView(
        kind: kind,
        onOpenMenu: onOpenMenu,
      ),
    );
  }
}

class _MarketKindPaneView extends StatefulWidget {
  const _MarketKindPaneView({
    required this.kind,
    required this.onOpenMenu,
  });

  final MarketAssetKind kind;
  final VoidCallback onOpenMenu;

  @override
  State<_MarketKindPaneView> createState() => _MarketKindPaneViewState();
}

class _MarketKindPaneViewState extends State<_MarketKindPaneView> {
  DataSourceSettings? _dataSources;
  List<Quote>? _groupedQuotesSource;
  MarketKindGroup? _cachedGroup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<DataSourceSettings>();
    if (!identical(_dataSources, next)) {
      _dataSources?.removeListener(_onDataSourcesChanged);
      _dataSources = next..addListener(_onDataSourcesChanged);
    }
  }

  @override
  void dispose() {
    _dataSources?.removeListener(_onDataSourcesChanged);
    super.dispose();
  }

  void _onDataSourcesChanged() {
    if (!mounted) return;
    final equities = context.read<EquityDataSourceRegistry>();
    final enabled = equities.enabledWhere(_dataSources!.isMarketEnabled);
    if (enabled.isNotEmpty) {
      context.read<QuotesListController>().refresh();
    } else {
      setState(() {});
    }
  }

  void _openAsset(String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  MarketKindGroup? _groupForKind(List<Quote> quotes) {
    if (identical(_groupedQuotesSource, quotes) && _cachedGroup != null) {
      return _cachedGroup;
    }
    final matching = groupQuotesByKindAndExchange(quotes)
        .where((g) => g.kind == widget.kind);
    final group = matching.isEmpty ? null : matching.first;
    _groupedQuotesSource = quotes;
    _cachedGroup = group;
    return group;
  }

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final title = widget.kind.label;

    return MasterDetailContentPane(
      title: title,
      subtitle:
          'Grouped by exchange. Load more for the next page of symbols.',
      onOpenMenu: widget.onOpenMenu,
      trailing: const AgentLaunchButton(
        intent: AgentLaunchIntent.explainMarketsLiteracy,
        outline: true,
      ),
      body: enabledEquities.isEmpty
          ? const AppEmptyView(AppCopy.noMarketSourcesEnabled)
          : QuotesPagingErrorListener(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SymbolSearchBar(onSymbolSelected: _openAsset),
                  Expanded(
                    child: QuotesAsyncBody(
                      errorTitle: 'Could not load $title',
                      builder: (context, quotes) {
                        final group = _groupForKind(quotes);
                        if (group == null || group.exchanges.isEmpty) {
                          return const AppEmptyView(AppCopy.noQuotes);
                        }
                        return _VirtualizedExchangeQuotes(
                          group: group,
                          onOpenAsset: _openAsset,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Flat [ListView.builder] of exchange headers + quote rows (virtualized).
class _VirtualizedExchangeQuotes extends StatelessWidget {
  const _VirtualizedExchangeQuotes({
    required this.group,
    required this.onOpenAsset,
  });

  final MarketKindGroup group;
  final ValueChanged<String> onOpenAsset;

  @override
  Widget build(BuildContext context) {
    final density = context.select<DisplaySettings, ListDensity>(
      (d) => d.listDensity,
    );
    final gap = density == ListDensity.compact ? 4.0 : 8.0;
    final entries = <_ListEntry>[];
    for (final exchangeGroup in group.exchanges) {
      entries.add(_ListEntry.header(exchangeGroup.exchange));
      for (final quote in exchangeGroup.quotes) {
        entries.add(_ListEntry.quote(quote));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return const QuotesLoadMoreBar();
        }
        final entry = entries[index];
        if (entry.isHeader) {
          return Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : 12,
              bottom: density == ListDensity.compact ? 4 : 6,
            ),
            child: _ExchangeCaption(entry.exchange!),
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: QuoteListTile(
            key: ValueKey(entry.quote!.symbol),
            quote: entry.quote!,
            density: density,
            onTap: () => onOpenAsset(entry.quote!.symbol),
          ),
        );
      },
    );
  }
}

class _ListEntry {
  const _ListEntry.header(this.exchange)
      : quote = null,
        isHeader = true;

  const _ListEntry.quote(this.quote)
      : exchange = null,
        isHeader = false;

  final String? exchange;
  final Quote? quote;
  final bool isHeader;
}

/// Single-exchange caption: name plus muted blurb when known.
class _ExchangeCaption extends StatelessWidget {
  const _ExchangeCaption(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final blurb = exchangeDescription(name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(name),
        if (blurb != null) ...[
          const SizedBox(height: 2),
          Text(
            blurb,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}
