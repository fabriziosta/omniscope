import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/formatting.dart';
import '../data/market/models.dart';
import '../data/settings/display_settings.dart';
import '../data/settings/favorites_repository.dart';
import 'tappable_nav_row.dart';

/// Shared Markets / Crypto quote row — respects [ListDensity] and [PriceFormat].
class QuoteListTile extends StatelessWidget {
  const QuoteListTile({
    super.key,
    required this.quote,
    required this.onTap,
    this.density = ListDensity.comfortable,
    this.cryptoExchangeId,
    this.showFavorite = true,
  });

  final Quote quote;
  final VoidCallback onTap;
  final ListDensity density;

  /// When non-null, the star toggles a crypto favorite for this exchange.
  /// When null, the star toggles a Markets favorite.
  final String? cryptoExchangeId;

  /// Hide the star (e.g. non-quote surfaces). Defaults to on.
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.watch<DisplaySettings>().priceFormat;
    final priceText = formatDisplayMoney(quote.price, priceFormat);
    final changeColor = quote.isUp
        ? BrandColors.gainOf(context)
        : BrandColors.lossOf(context);
    final compact = density == ListDensity.compact;
    final changeText =
        '${formatSignedMoney(quote.change)}  ${formatPercent(quote.changePercent)}';

    final favoriteButton = showFavorite
        ? _FavoriteStarButton(
            symbol: quote.symbol,
            cryptoExchangeId: cryptoExchangeId,
            compact: compact,
          )
        : null;

    if (compact) {
      final source = quote.dataSource?.trim();
      return TappableNavRow(
        onTap: onTap,
        compact: true,
        leading: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: quote.symbol,
                style: theme.textTheme.large,
              ),
              if (source != null && source.isNotEmpty) ...[
                TextSpan(
                  text: '  ·  ',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                TextSpan(
                  text: source,
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (favoriteButton != null) ...[
              favoriteButton,
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: priceText,
                      style: theme.textTheme.large,
                    ),
                    TextSpan(
                      text: '  $changeText',
                      style: theme.textTheme.small.copyWith(color: changeColor),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
    }

    return TappableNavRow(
      onTap: onTap,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote.symbol, style: theme.textTheme.large),
          if (quote.name != null) ...[
            const SizedBox(height: 2),
            Text(
              quote.name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.muted,
            ),
          ],
          if (quote.dataSource != null) ...[
            const SizedBox(height: 2),
            Text(
              quote.dataSource!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (favoriteButton != null) ...[
            favoriteButton,
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(priceText, style: theme.textTheme.large),
              const SizedBox(height: 2),
              Text(
                changeText,
                style: theme.textTheme.small.copyWith(color: changeColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteStarButton extends StatelessWidget {
  const _FavoriteStarButton({
    required this.symbol,
    required this.cryptoExchangeId,
    required this.compact,
  });

  final String symbol;
  final String? cryptoExchangeId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final favorites = context.watch<FavoritesRepository>();
    final favorited = cryptoExchangeId == null
        ? favorites.isMarketFavorite(symbol)
        : favorites.isCryptoFavorite(cryptoExchangeId!, symbol);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final repo = context.read<FavoritesRepository>();
        if (cryptoExchangeId == null) {
          repo.toggleMarketFavorite(symbol);
        } else {
          repo.toggleCryptoFavorite(cryptoExchangeId!, symbol);
        }
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            favorited ? LucideIcons.star : LucideIcons.starOff,
            size: compact ? 18 : 20,
            color: favorited
                ? theme.colorScheme.primary
                : theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}
