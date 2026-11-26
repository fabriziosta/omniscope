import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/favorites_quotes_pane.dart';

/// Markets Favorites content pane (all starred symbols).
class MarketFavoritesPane extends StatelessWidget {
  const MarketFavoritesPane({
    super.key,
    required this.onOpenMenu,
  });

  final VoidCallback onOpenMenu;

  Future<void> _clearAll(BuildContext context) async {
    final favorites = context.read<FavoritesRepository>();
    final count = favorites.symbols.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear all favorites?',
      description: count == 0
          ? 'Removes every starred Markets symbol from the data file. '
              'This cannot be undone.'
          : 'Removes $count '
              '${count == 1 ? 'favorite' : 'favorites'} from the data file. '
              'This cannot be undone.',
      confirmLabel: 'Clear favorites',
    );
    if (!ok || !context.mounted) return;
    await favorites.clearAll();
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Favorites cleared',
      description: 'Starred Markets symbols were removed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final crypto = context.watch<CryptoExchangeRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final enabledCrypto = crypto.enabledWhere(dataSources.isCryptoEnabled);
    final favorites = context.watch<FavoritesRepository>();
    final symbols = favorites.symbols;
    final noSources = enabledEquities.isEmpty && enabledCrypto.isEmpty;

    return FavoritesQuotesPane(
      symbols: symbols,
      subtitle:
          'Symbols you starred in Markets. Long-press and drag to reorder, '
          'or tap the star again to remove.',
      emptyMessage: AppCopy.noMarketFavorites,
      blockedMessage: noSources ? AppCopy.noMarketSourcesEnabled : null,
      onOpenMenu: onOpenMenu,
      onClearAll: () => _clearAll(context),
      clearAllLabel: 'Clear all',
      onReorder: (oldIndex, newIndex) async {
        await favorites.reorderFavorites(oldIndex, newIndex);
        return favorites.symbols;
      },
    );
  }
}
