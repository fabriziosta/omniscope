import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/formatting.dart';
import '../data/agents/agent_launch.dart';
import '../data/market/models.dart';
import '../data/settings/display_settings.dart';
import '../data/settings/favorites_repository.dart';
import 'agent_launch_button.dart';
import 'app_tooltip.dart';
import 'tappable_nav_row.dart';

/// Shared Markets / Crypto quote row — respects [ListDensity] and [PriceFormat].
///
/// Both densities keep a two-line identity (symbol + name/venue) so the row is
/// readable before opening asset detail; compact only tightens padding/gaps.
class QuoteListTile extends StatelessWidget {
  const QuoteListTile({
    super.key,
    required this.quote,
    required this.onTap,
    this.density = ListDensity.comfortable,
    this.cryptoExchangeId,
    this.showFavorite = true,
    this.showInvestigate = true,
  });

  final Quote quote;
  final VoidCallback onTap;
  final ListDensity density;

  /// When non-null, the star toggles a crypto favorite for this exchange.
  /// When null, the star toggles a Markets favorite.
  final String? cryptoExchangeId;

  /// Hide the star (e.g. non-quote surfaces). Defaults to on.
  final bool showFavorite;

  /// Sparkles control that deep-links into Investigate for this symbol.
  final bool showInvestigate;

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
    final subtitle = quote.listSubtitle;
    final semanticsLabel =
        '${quote.symbol}${subtitle == null ? '' : ', $subtitle'}, '
        'price $priceText, change $changeText';

    final favoriteButton = showFavorite
        ? _FavoriteStarButton(
            symbol: quote.symbol,
            cryptoExchangeId: cryptoExchangeId,
            compact: compact,
          )
        : null;
    final investigateButton = showInvestigate
        ? AgentLaunchButton(
            symbol: quote.symbol,
            intent: AgentLaunchIntent.investigate,
            iconOnly: true,
          )
        : null;

    final leading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quote.symbol,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.large,
        ),
        if (subtitle != null) ...[
          SizedBox(height: compact ? 1 : 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.muted,
          ),
        ],
      ],
    );

    final priceColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          priceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: theme.textTheme.large,
        ),
        SizedBox(height: compact ? 1 : 2),
        Text(
          changeText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: theme.textTheme.small.copyWith(color: changeColor),
        ),
      ],
    );

    final row = TappableNavRow(
      onTap: onTap,
      compact: compact,
      leading: leading,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?investigateButton,
          if (favoriteButton != null) ...[
            favoriteButton,
            SizedBox(width: compact ? 4 : 8),
          ],
          Flexible(child: priceColumn),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: row,
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
    final label =
        favorited ? 'Remove $symbol from favorites' : 'Add $symbol to favorites';

    return Semantics(
      button: true,
      label: label,
      child: AppTooltip(
        message: favorited ? 'Remove from favorites' : 'Add to favorites',
        wrapDetector: true,
        child: GestureDetector(
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
        ),
      ),
    );
  }
}
