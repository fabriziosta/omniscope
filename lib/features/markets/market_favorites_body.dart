import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/market_data_client.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Markets Favorites content pane (starred equity symbols).
class MarketFavoritesPane extends StatelessWidget {
  const MarketFavoritesPane({
    super.key,
    required this.showBack,
    this.onBack,
  });

  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final symbols = context.watch<FavoritesRepository>().marketSymbols;
    return ChangeNotifierProvider(
      key: ValueKey(symbols.join('|')),
      create: (context) => QuotesListController(
        client: context.read<MarketDataClient>(),
        symbols: symbols,
        errorTitle: 'Could not load Favorites',
      )..refresh(),
      child: _MarketFavoritesPaneView(
        showBack: showBack,
        onBack: onBack,
      ),
    );
  }
}

class _MarketFavoritesPaneView extends StatelessWidget {
  const _MarketFavoritesPaneView({
    required this.showBack,
    this.onBack,
  });

  final bool showBack;
  final VoidCallback? onBack;

  void _openAsset(BuildContext context, String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final favorites = context.watch<FavoritesRepository>();
    final density = context.watch<DisplaySettings>().listDensity;
    final gap = density == ListDensity.compact ? 6.0 : 10.0;
    final controller = context.watch<QuotesListController>();

    return MasterDetailContentPane(
      title: 'Favorites',
      subtitle:
          'Symbols you starred in Markets. Tap the star again to remove.',
      showBack: showBack,
      onBack: onBack,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        enabled: enabledEquities.isNotEmpty &&
            favorites.marketSymbols.isNotEmpty &&
            !controller.loading &&
            !controller.loadingMore,
        onPressed: controller.refresh,
        child: const Text('Refresh'),
      ),
      body: enabledEquities.isEmpty
          ? const AppEmptyView(AppCopy.noMarketSourcesEnabled)
          : favorites.marketSymbols.isEmpty
              ? const AppEmptyView(AppCopy.noMarketFavorites)
              : QuotesAsyncBody(
                  errorTitle: 'Could not load Favorites',
                  builder: (context, quotes) {
                    if (quotes.isEmpty) {
                      return const AppEmptyView(AppCopy.noQuotes);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: quotes.length,
                      itemBuilder: (context, index) {
                        final quote = quotes[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index < quotes.length - 1 ? gap : 0,
                          ),
                          child: QuoteListTile(
                            quote: quote,
                            density: density,
                            onTap: () => _openAsset(context, quote.symbol),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
