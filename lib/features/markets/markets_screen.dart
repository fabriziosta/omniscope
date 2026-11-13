import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/tab_page_header.dart';
import 'market_favorites_body.dart';
import 'market_kind_body.dart';

/// Sidebar destinations for Markets (Favorites + asset kinds).
enum MarketsNavItem {
  favorites,
  indices,
  etfs,
  stocks,
}

extension MarketsNavItemX on MarketsNavItem {
  String get title => switch (this) {
        MarketsNavItem.favorites => 'Favorites',
        MarketsNavItem.indices => MarketAssetKind.indices.label,
        MarketsNavItem.etfs => MarketAssetKind.etfs.label,
        MarketsNavItem.stocks => MarketAssetKind.stocks.label,
      };

  MarketAssetKind? get kind => switch (this) {
        MarketsNavItem.favorites => null,
        MarketsNavItem.indices => MarketAssetKind.indices,
        MarketsNavItem.etfs => MarketAssetKind.etfs,
        MarketsNavItem.stocks => MarketAssetKind.stocks,
      };

  IconData get icon => switch (this) {
        MarketsNavItem.favorites => LucideIcons.star,
        MarketsNavItem.indices => LucideIcons.lineChart,
        MarketsNavItem.etfs => LucideIcons.pieChart,
        MarketsNavItem.stocks => LucideIcons.trendingUp,
      };
}

/// Markets group — Favorites, Indices, ETFs, Stocks via master–detail.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  MarketsNavItem _selected = MarketsNavItem.indices;
  MarketsNavItem? _narrowSelected;

  void _select(MarketsNavItem item, {required bool wide}) {
    setState(() {
      _selected = item;
      if (!wide) {
        _narrowSelected = item;
      }
    });
  }

  void _backToNavList() {
    setState(() => _narrowSelected = null);
  }

  String _metaFor(MarketsNavItem item, FavoritesRepository favorites) {
    if (item == MarketsNavItem.favorites) {
      final count = favorites.marketSymbols.length;
      return count == 1 ? '1 symbol' : '$count symbols';
    }
    final kind = item.kind!;
    final count = watchlistSymbolsForKind(kind).length;
    return count == 1 ? '1 symbol' : '$count symbols';
  }

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final favorites = context.watch<FavoritesRepository>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final hasSources = enabledEquities.isNotEmpty;

    return InTabBackEffect(
      onBack: _narrowSelected != null ? _backToNavList : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_narrowSelected == null)
            const TabPageHeader(
              title: 'Markets',
              subtitle:
                  'Browse by type. Favorites, Indices, ETFs, or Stocks.',
            ),
          Expanded(
            child: !hasSources
                ? const AppEmptyView(AppCopy.noMarketSourcesEnabled)
                : MasterDetailShell<MarketsNavItem>(
                    selected: _selected,
                    narrowSelected: _narrowSelected,
                    onNarrowBack: _backToNavList,
                    sidebarBuilder: (context, highlighted, {required wide}) {
                      return MasterDetailNavList(
                        tiles: [
                          for (final item in MarketsNavItem.values)
                            MasterDetailNavTile(
                              title: item.title,
                              meta: _metaFor(item, favorites),
                              icon: item.icon,
                              selected: highlighted == item,
                              onTap: () => _select(item, wide: wide),
                            ),
                        ],
                      );
                    },
                    contentBuilder:
                        (context, item, {required showBack, onBack}) {
                      if (item == MarketsNavItem.favorites) {
                        return MarketFavoritesPane(
                          key: const ValueKey('markets-favorites'),
                          showBack: showBack,
                          onBack: onBack,
                          backLabel: 'Markets',
                        );
                      }
                      final kind = item.kind!;
                      return MarketKindPane(
                        key: ValueKey(kind),
                        kind: kind,
                        showBack: showBack,
                        onBack: onBack,
                        backLabel: 'Markets',
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
