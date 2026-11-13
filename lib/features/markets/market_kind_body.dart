import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/market_data_client.dart';
import '../../data/market/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../../widgets/quotes_load_more_bar.dart';
import '../../widgets/section_caption.dart';
import '../../widgets/themed_accordion_item.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Markets subgroup content pane: header chrome + quote list for [kind].
///
/// Remount with a [ValueKey] on [kind] when the sidebar selection changes.
class MarketKindPane extends StatelessWidget {
  const MarketKindPane({
    super.key,
    required this.kind,
    required this.showBack,
    this.onBack,
  });

  final MarketAssetKind kind;
  final bool showBack;
  final VoidCallback? onBack;

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
        showBack: showBack,
        onBack: onBack,
      ),
    );
  }
}

class _MarketKindPaneView extends StatefulWidget {
  const _MarketKindPaneView({
    required this.kind,
    required this.showBack,
    this.onBack,
  });

  final MarketAssetKind kind;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<_MarketKindPaneView> createState() => _MarketKindPaneViewState();
}

class _MarketKindPaneViewState extends State<_MarketKindPaneView> {
  DataSourceSettings? _dataSources;

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

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final controller = context.watch<QuotesListController>();
    final title = widget.kind.label;

    return MasterDetailContentPane(
      title: title,
      subtitle:
          'Grouped by exchange. Load more for the next page of symbols.',
      showBack: widget.showBack,
      onBack: widget.onBack,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        enabled: enabledEquities.isNotEmpty &&
            !controller.loading &&
            !controller.loadingMore,
        onPressed: controller.refresh,
        child: const Text('Refresh'),
      ),
      body: enabledEquities.isEmpty
          ? const AppEmptyView(AppCopy.noMarketSourcesEnabled)
          : QuotesAsyncBody(
              errorTitle: 'Could not load $title',
              builder: (context, quotes) {
                final matching = groupQuotesByKindAndExchange(quotes)
                    .where((g) => g.kind == widget.kind);
                final group = matching.isEmpty ? null : matching.first;
                if (group == null || group.exchanges.isEmpty) {
                  return const AppEmptyView(AppCopy.noQuotes);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _ExchangeSubgroups(
                      group: group,
                      onOpenAsset: _openAsset,
                    ),
                    const QuotesLoadMoreBar(),
                  ],
                );
              },
            ),
    );
  }
}

class _ExchangeSubgroups extends StatelessWidget {
  const _ExchangeSubgroups({
    required this.group,
    required this.onOpenAsset,
  });

  final MarketKindGroup group;
  final ValueChanged<String> onOpenAsset;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final exchanges = group.exchanges;

    // Single exchange: skip a redundant nested accordion header.
    if (exchanges.length == 1) {
      return _QuoteList(
        quotes: exchanges.first.quotes,
        onOpenAsset: onOpenAsset,
        exchangeLabel: exchanges.first.exchange,
      );
    }

    return ShadAccordion<String>.multiple(
      initialValue: exchanges.map((e) => e.exchange).toList(),
      children: [
        for (final exchangeGroup in exchanges)
          ThemedAccordionItem<String>(
            value: exchangeGroup.exchange,
            title: Text(
              '${exchangeGroup.exchange}  ·  ${exchangeGroup.quotes.length}',
              style: theme.textTheme.large,
              overflow: TextOverflow.ellipsis,
            ),
            child: _QuoteList(
              quotes: exchangeGroup.quotes,
              onOpenAsset: onOpenAsset,
            ),
          ),
      ],
    );
  }
}

class _QuoteList extends StatelessWidget {
  const _QuoteList({
    required this.quotes,
    required this.onOpenAsset,
    this.exchangeLabel,
  });

  final List<Quote> quotes;
  final ValueChanged<String> onOpenAsset;
  final String? exchangeLabel;

  @override
  Widget build(BuildContext context) {
    final density = context.watch<DisplaySettings>().listDensity;
    final gap = density == ListDensity.compact ? 6.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (exchangeLabel != null) ...[
          Padding(
            padding: EdgeInsets.only(
              bottom: density == ListDensity.compact ? 6 : 8,
            ),
            child: SectionCaption(exchangeLabel!),
          ),
        ],
        for (var i = 0; i < quotes.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          QuoteListTile(
            quote: quotes[i],
            density: density,
            onTap: () => onOpenAsset(quotes[i].symbol),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
