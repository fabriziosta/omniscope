import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/market/models.dart';
import '../../data/settings/data_source_settings.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../crypto/crypto_exchange_pairs_body.dart';
import 'market_favorites_body.dart';
import 'market_invest_interest_body.dart';
import 'market_kind_body.dart';

/// Sidebar destinations for Markets (Favorites, equity kinds, crypto venues).
sealed class MarketsDestination {
  const MarketsDestination();

  String get id;
  String get title;
  IconData get icon;
}

final class MarketsFavoritesDestination extends MarketsDestination {
  const MarketsFavoritesDestination();

  @override
  String get id => 'favorites';

  @override
  String get title => 'Favorites';

  @override
  IconData get icon => LucideIcons.star;
}

final class MarketsInvestInterestDestination extends MarketsDestination {
  const MarketsInvestInterestDestination();

  @override
  String get id => 'investInterest';

  @override
  String get title => 'Invest interest';

  @override
  IconData get icon => LucideIcons.crosshair;
}

final class MarketsKindDestination extends MarketsDestination {
  const MarketsKindDestination(this.kind);

  final MarketAssetKind kind;

  @override
  String get id => 'kind:${kind.name}';

  @override
  String get title => kind.label;

  @override
  IconData get icon => switch (kind) {
        MarketAssetKind.indices => LucideIcons.lineChart,
        MarketAssetKind.etfs => LucideIcons.pieChart,
        MarketAssetKind.stocks => LucideIcons.trendingUp,
        MarketAssetKind.crypto => LucideIcons.bitcoin,
      };
}

final class MarketsCryptoDestination extends MarketsDestination {
  const MarketsCryptoDestination({
    required this.exchangeId,
    required this.displayName,
  });

  final String exchangeId;
  final String displayName;

  @override
  String get id => 'crypto:$exchangeId';

  @override
  String get title => displayName;

  @override
  IconData get icon => LucideIcons.bitcoin;
}

/// Markets group — Favorites, equities by kind, and spot crypto by exchange.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  String _selectedId = const MarketsKindDestination(MarketAssetKind.indices).id;

  void _select(MarketsDestination item) {
    setState(() => _selectedId = item.id);
  }

  MarketsDestination? _byId(List<MarketsDestination> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<MarketsDestination> _destinations({
    required bool hasEquities,
    required List<CryptoExchangeClient> exchanges,
  }) {
    return [
      const MarketsFavoritesDestination(),
      const MarketsInvestInterestDestination(),
      if (hasEquities) ...[
        for (final kind in marketTabKinds) MarketsKindDestination(kind),
      ],
      for (final client in exchanges)
        MarketsCryptoDestination(
          exchangeId: client.exchange.id,
          displayName: client.exchange.displayName,
        ),
    ];
  }

  String? _metaFor(MarketsDestination item) {
    return switch (item) {
      MarketsCryptoDestination() => 'Spot pairs',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final crypto = context.watch<CryptoExchangeRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final enabledCrypto = crypto.enabledWhere(dataSources.isCryptoEnabled);
    final hasEquities = enabledEquities.isNotEmpty;
    final hasCrypto = enabledCrypto.isNotEmpty;
    final hasSources = hasEquities || hasCrypto;

    final destinations = _destinations(
      hasEquities: hasEquities,
      exchanges: enabledCrypto,
    );
    final selected = _byId(destinations, _selectedId) ??
        (destinations.isEmpty ? null : destinations.first);

    // Keep selection valid when sources are toggled off.
    if (selected != null && selected.id != _selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedId = selected.id);
      });
    }

    return !hasSources || selected == null
        ? const AppEmptyView(AppCopy.noMarketSourcesEnabled)
        : MasterDetailShell<MarketsDestination>(
            selected: selected,
            sidebarBuilder: (context, highlighted, {required closeNav}) {
              return MasterDetailNavList(
                tiles: [
                  for (final item in destinations)
                    MasterDetailNavTile(
                      title: item.title,
                      meta: _metaFor(item),
                      icon: item.icon,
                      selected: highlighted.id == item.id,
                      onTap: () {
                        _select(item);
                        closeNav();
                      },
                    ),
                ],
              );
            },
            contentBuilder: (context, item, {required onOpenMenu}) {
              switch (item) {
                case MarketsFavoritesDestination():
                  return MarketFavoritesPane(
                    key: const ValueKey('markets-favorites'),
                    onOpenMenu: onOpenMenu,
                  );
                case MarketsInvestInterestDestination():
                  return MarketInvestInterestPane(
                    key: const ValueKey('markets-invest-interest'),
                    onOpenMenu: onOpenMenu,
                  );
                case MarketsKindDestination(:final kind):
                  return MarketKindPane(
                    key: ValueKey(kind),
                    kind: kind,
                    onOpenMenu: onOpenMenu,
                  );
                case MarketsCryptoDestination(:final exchangeId):
                  CryptoExchangeClient? client;
                  for (final c in enabledCrypto) {
                    if (c.exchange.id == exchangeId) {
                      client = c;
                      break;
                    }
                  }
                  if (client == null) {
                    return const AppEmptyView(
                      AppCopy.noCryptoExchangesEnabled,
                    );
                  }
                  return CryptoExchangePairsPane(
                    key: ValueKey(exchangeId),
                    client: client,
                    onOpenMenu: onOpenMenu,
                  );
              }
            },
          );
  }
}
