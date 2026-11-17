import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/favorites_quotes_pane.dart';

/// Markets Invest interest content pane (agent-facing symbol list).
class MarketInvestInterestPane extends StatelessWidget {
  const MarketInvestInterestPane({
    super.key,
    required this.onOpenMenu,
  });

  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final dataSources = context.watch<DataSourceSettings>();
    final equities = context.watch<EquityDataSourceRegistry>();
    final crypto = context.watch<CryptoExchangeRegistry>();
    final enabledEquities =
        equities.enabledWhere(dataSources.isMarketEnabled);
    final enabledCrypto = crypto.enabledWhere(dataSources.isCryptoEnabled);
    final favorites = context.watch<FavoritesRepository>();
    final symbols = favorites.investInterestSymbols;
    final noSources = enabledEquities.isEmpty && enabledCrypto.isEmpty;
    final managed = favorites.investInterestManagedByAgent;
    final subtitle = managed
        ? AppCopy.investInterestManagedByAgent
        : 'Assets you want agents to consider investing in. '
            'Long-press and drag to reorder, or tap the target again to remove.';

    return FavoritesQuotesPane(
      title: 'Invest interest',
      errorTitle: 'Could not load Invest interest',
      symbols: symbols,
      subtitle: subtitle,
      emptyMessage: AppCopy.noInvestInterest,
      blockedMessage: noSources ? AppCopy.noMarketSourcesEnabled : null,
      onOpenMenu: onOpenMenu,
      onReorder: (oldIndex, newIndex) async {
        await favorites.reorderInvestInterest(oldIndex, newIndex);
        return favorites.investInterestSymbols;
      },
    );
  }
}
