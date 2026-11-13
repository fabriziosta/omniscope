import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../core/fade_page_route.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/market/market_data_client.dart';
import '../../data/settings/display_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/quote_list_tile.dart';
import '../../widgets/quotes_async_body.dart';
import '../asset_detail/asset_detail_screen.dart';
import '../quotes/quotes_list_controller.dart';

/// Favorited spot pairs pane for one crypto exchange.
class CryptoExchangeFavoritesPane extends StatelessWidget {
  const CryptoExchangeFavoritesPane({
    super.key,
    required this.client,
    required this.showBack,
    this.onBack,
  });

  final CryptoExchangeClient client;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final exchangeId = client.exchange.id;
    final symbols =
        context.watch<FavoritesRepository>().cryptoSymbolsFor(exchangeId);
    return ChangeNotifierProvider(
      key: ValueKey('$exchangeId|${symbols.join('|')}'),
      create: (context) => QuotesListController(
        client: context.read<MarketDataClient>(),
        symbols: symbols,
        errorTitle: 'Could not load Favorites',
      )..refresh(),
      child: _CryptoExchangeFavoritesPaneView(
        displayName: client.exchange.displayName,
        exchangeId: exchangeId,
        showBack: showBack,
        onBack: onBack,
      ),
    );
  }
}

class _CryptoExchangeFavoritesPaneView extends StatelessWidget {
  const _CryptoExchangeFavoritesPaneView({
    required this.displayName,
    required this.exchangeId,
    required this.showBack,
    this.onBack,
  });

  final String displayName;
  final String exchangeId;
  final bool showBack;
  final VoidCallback? onBack;

  void _openAsset(BuildContext context, String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesRepository>();
    final symbols = favorites.cryptoSymbolsFor(exchangeId);
    final density = context.watch<DisplaySettings>().listDensity;
    final gap = density == ListDensity.compact ? 6.0 : 10.0;
    final controller = context.watch<QuotesListController>();

    return MasterDetailContentPane(
      title: 'Favorites',
      subtitle:
          'Pairs you starred on $displayName. '
          'Tap the star again to remove.',
      showBack: showBack,
      onBack: onBack,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        enabled: symbols.isNotEmpty &&
            !controller.loading &&
            !controller.loadingMore,
        onPressed: controller.refresh,
        child: const Text('Refresh'),
      ),
      body: symbols.isEmpty
          ? const AppEmptyView(AppCopy.noCryptoFavorites)
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
                        cryptoExchangeId: exchangeId,
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
