import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/favorites_quotes_pane.dart';

/// Favorited spot pairs pane for one crypto exchange.
class CryptoExchangeFavoritesPane extends StatelessWidget {
  const CryptoExchangeFavoritesPane({
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
    final exchangeId = client.exchange.id;
    final displayName = client.exchange.displayName;
    final favorites = context.watch<FavoritesRepository>();
    final symbols = favorites.cryptoSymbolsFor(exchangeId);

    return FavoritesQuotesPane(
      symbols: symbols,
      membershipKeyPrefix: exchangeId,
      subtitle:
          'Pairs you starred on $displayName. Long-press and drag to reorder, '
          'or tap the star again to remove.',
      emptyMessage: AppCopy.noCryptoFavorites,
      cryptoExchangeId: exchangeId,
      showBack: showBack,
      onBack: onBack,
      backLabel: backLabel ?? displayName,
      onReorder: (oldIndex, newIndex) async {
        await favorites.reorderCryptoFavorites(
          exchangeId,
          oldIndex,
          newIndex,
        );
        return favorites.cryptoSymbolsFor(exchangeId);
      },
    );
  }
}
