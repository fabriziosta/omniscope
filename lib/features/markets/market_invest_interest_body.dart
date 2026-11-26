import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/market/equity_data_source.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/invest_interest_provenance.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/favorites_quotes_pane.dart';

/// Markets Invest interest content pane (agent-facing symbol list).
class MarketInvestInterestPane extends StatelessWidget {
  const MarketInvestInterestPane({
    super.key,
    required this.onOpenMenu,
  });

  final VoidCallback onOpenMenu;

  Future<void> _clearAll(BuildContext context) async {
    final favorites = context.read<FavoritesRepository>();
    final count = favorites.investInterestSymbols.length;
    final ok = await confirmDestructiveAction(
      context,
      title: 'Clear invest interest?',
      description: count == 0
          ? 'Removes every Invest interest symbol from the data file. '
              'This cannot be undone.'
          : 'Removes $count invest-interest '
              '${count == 1 ? 'symbol' : 'symbols'} from the data file. '
              'This cannot be undone.',
      confirmLabel: 'Clear invest interest',
    );
    if (!ok || !context.mounted) return;
    await favorites.clearInvestInterest();
    if (!context.mounted) return;
    showAppToast(
      context,
      title: 'Invest interest cleared',
      description: 'Agent-facing invest-interest symbols were removed.',
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
      onClearAll: () => _clearAll(context),
      clearAllLabel: 'Clear all',
      sourceLabelFor: (symbol) => favorites.sourceFor(symbol).label,
      sourceIsAgentFor: (symbol) =>
          favorites.sourceFor(symbol) == InvestInterestSource.agent,
      onReorder: (oldIndex, newIndex) async {
        await favorites.reorderInvestInterest(oldIndex, newIndex);
        return favorites.investInterestSymbols;
      },
    );
  }
}
