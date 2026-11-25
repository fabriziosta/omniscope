import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/market/market_data_client.dart';
import '../../data/settings/display_settings.dart';
import '../../widgets/agent_launch_button.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../../widgets/quotes_load_more_bar.dart';
import '../../widgets/quotes_paging_error_listener.dart';
import '../../widgets/symbol_search.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Spot pairs content pane for one [CryptoExchangeClient].
class CryptoExchangePairsPane extends StatelessWidget {
  const CryptoExchangePairsPane({
    super.key,
    required this.client,
    required this.onOpenMenu,
  });

  final CryptoExchangeClient client;
  final VoidCallback onOpenMenu;

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
          // Discover the live catalog first so delisted curated symbols never
          // hit get-tickers (HTTP 400) on the opening page.
          try {
            final discovered = await client.browseSymbols();
            if (discovered.isNotEmpty) {
              controller.updateSymbols(discovered);
            }
          } catch (_) {
            // Keep curated defaults; refresh still runs below.
          }
          await controller.refresh();
        }();
        return controller;
      },
      child: _CryptoExchangePairsPaneView(
        displayName: client.exchange.displayName,
        exchangeId: client.exchange.id,
        onOpenMenu: onOpenMenu,
      ),
    );
  }
}

class _CryptoExchangePairsPaneView extends StatelessWidget {
  const _CryptoExchangePairsPaneView({
    required this.displayName,
    required this.exchangeId,
    required this.onOpenMenu,
  });

  final String displayName;
  final String exchangeId;
  final VoidCallback onOpenMenu;

  void _openAsset(BuildContext context, String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final density = context.watch<DisplaySettings>().listDensity;
    final compact = density == ListDensity.compact;
    final gap = compact ? 4.0 : 8.0;

    return MasterDetailContentPane(
      title: 'Spot pairs',
      subtitle:
          '$displayName spot USD pairs (public market data). '
          'Load more to browse additional instruments.',
      onOpenMenu: onOpenMenu,
      trailing: AgentLaunchButton(
        intent: AgentLaunchIntent.explainCryptoSpot,
        exchangeId: exchangeId,
        outline: true,
        showTradeOption: false,
      ),
      body: QuotesPagingErrorListener(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SymbolSearchBar(
              onSymbolSelected: (symbol) => _openAsset(context, symbol),
            ),
            Expanded(
              child: QuotesAsyncBody(
                errorTitle: 'Could not load crypto',
                builder: (context, quotes) {
                  if (quotes.isEmpty) {
                    return const AppEmptyView(AppCopy.noQuotes);
                  }
                  return ListView.builder(
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
                          cryptoExchangeId: exchangeId,
                          onTap: () => _openAsset(context, quote.symbol),
                        ),
                      );
                    },
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
