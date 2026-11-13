import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/market/market_data_client.dart';
import '../../data/settings/display_settings.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../../widgets/quotes_filter_field.dart';
import '../../widgets/quotes_load_more_bar.dart';
import '../../widgets/quotes_paging_error_listener.dart';
import '../../widgets/quotes_refresh_body.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Spot pairs content pane for one [CryptoExchangeClient].
class CryptoExchangePairsPane extends StatelessWidget {
  const CryptoExchangePairsPane({
    super.key,
    required this.client,
    required this.showBack,
    this.onBack,
    this.backLabel,
  });

  final CryptoExchangeClient client;
  final bool showBack;
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final controller = QuotesListController(
          client: context.read<MarketDataClient>(),
          symbols: client.exchange.defaultSymbols,
          errorTitle: 'Could not load crypto',
        );
        () async {
          final first = controller.refresh();
          final discovered = await client.browseSymbols();
          final same = discovered.length == controller.symbols.length &&
              discovered.every(controller.symbols.contains);
          if (!same) {
            controller.updateSymbols(discovered);
            await controller.refresh();
          } else {
            await first;
          }
        }();
        return controller;
      },
      child: _CryptoExchangePairsPaneView(
        displayName: client.exchange.displayName,
        exchangeId: client.exchange.id,
        showBack: showBack,
        onBack: onBack,
        backLabel: backLabel ?? client.exchange.displayName,
      ),
    );
  }
}

class _CryptoExchangePairsPaneView extends StatefulWidget {
  const _CryptoExchangePairsPaneView({
    required this.displayName,
    required this.exchangeId,
    required this.showBack,
    required this.backLabel,
    this.onBack,
  });

  final String displayName;
  final String exchangeId;
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<_CryptoExchangePairsPaneView> createState() =>
      _CryptoExchangePairsPaneViewState();
}

class _CryptoExchangePairsPaneViewState
    extends State<_CryptoExchangePairsPaneView> {
  final _filterController = TextEditingController();
  Timer? _filterDebounce;

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterChanged(String value) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<QuotesListController>().setSymbolQuery(value);
    });
  }

  void _openAsset(String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final density = context.watch<DisplaySettings>().listDensity;
    final compact = density == ListDensity.compact;
    final gap = compact ? 6.0 : 10.0;
    final controller = context.watch<QuotesListController>();

    return MasterDetailContentPane(
      title: 'Spot pairs',
      subtitle:
          '${widget.displayName} spot USD pairs (public market data). '
          'Load more to browse additional instruments.',
      showBack: widget.showBack,
      onBack: widget.onBack,
      backLabel: widget.backLabel,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        enabled: !controller.loading && !controller.loadingMore,
        onPressed: controller.refresh,
        child: const Text('Refresh'),
      ),
      body: QuotesPagingErrorListener(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuotesFilterField(
              controller: _filterController,
              onChanged: _onFilterChanged,
            ),
            Expanded(
              child: QuotesAsyncBody(
                errorTitle: 'Could not load crypto',
                builder: (context, quotes) {
                  if (quotes.isEmpty) {
                    return AppEmptyView(
                      controller.symbolQuery.isEmpty
                          ? AppCopy.noQuotes
                          : AppCopy.noQuotesMatchFilter,
                    );
                  }
                  return QuotesRefreshBody(
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: quotes.length + 1,
                      itemBuilder: (context, index) {
                        if (index == quotes.length) {
                          return const QuotesLoadMoreBar();
                        }
                        final quote = quotes[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index < quotes.length - 1 ? gap : 0,
                          ),
                          child: QuoteListTile(
                            quote: quote,
                            density: density,
                            cryptoExchangeId: widget.exchangeId,
                            onTap: () => _openAsset(quote.symbol),
                          ),
                        );
                      },
                    ),
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
