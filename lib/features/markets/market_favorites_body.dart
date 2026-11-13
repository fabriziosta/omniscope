import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/favorites_quotes_pane.dart';

/// Markets Favorites content pane (starred equity symbols).
class MarketFavoritesPane extends StatelessWidget {
  const MarketFavoritesPane({
    super.key,
    required this.showBack,
    this.onBack,
    this.backLabel = 'Markets',
  });

  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final favorites = context.watch<FavoritesRepository>();
    final symbols = favorites.marketSymbols;

    return FavoritesQuotesPane(
      symbols: symbols,
      subtitle:
          'Symbols you starred in Markets. Long-press and drag to reorder, '
          'or tap the star again to remove.',
      emptyMessage: AppCopy.noMarketFavorites,
      blockedMessage:
          enabledEquities.isEmpty ? AppCopy.noMarketSourcesEnabled : null,
      showBack: showBack,
      onBack: onBack,
      backLabel: backLabel,
      onReorder: (oldIndex, newIndex) async {
        await favorites.reorderMarketFavorites(oldIndex, newIndex);
        return favorites.marketSymbols;
      },
    );
  }
}
