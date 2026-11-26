import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/brand_colors.dart';
import '../core/formatting.dart';
import '../data/agents/agent_launch.dart';
import '../data/market/models.dart';
import '../data/settings/display_settings.dart';
import '../data/settings/favorites_repository.dart';
import '../features/agents/agent_launch_actions.dart';
import 'agent_launch_button.dart';
import 'app_text.dart';
import 'app_tooltip.dart';
import 'overflow_actions_menu.dart';
import 'tappable_nav_row.dart';

/// Shared Markets / Crypto quote row — respects [ListDensity] and [PriceFormat].
///
/// Both densities keep a two-line identity (symbol + name/venue) so the row is
/// readable before opening asset detail; compact only tightens padding/gaps.
/// On narrow windows, secondary CTAs collapse into a ⋯ menu.
class QuoteListTile extends StatelessWidget {
  const QuoteListTile({
    super.key,
    required this.quote,
    required this.onTap,
    this.density = ListDensity.compact,
    this.cryptoExchangeId,
    this.showFavorite = true,
    this.showInvestInterest = true,
    this.showInvestigate = true,
    this.sourceLabel,
    this.sourceIsAgent = false,
  });

  final Quote quote;
  final VoidCallback onTap;
  final ListDensity density;

  /// Optional venue id for crypto rows (display / future routing); stars use
  /// the shared Favorites list by symbol only.
  final String? cryptoExchangeId;

  /// Hide the star (e.g. non-quote surfaces). Defaults to on.
  final bool showFavorite;

  /// Hide the invest-interest target. Defaults to on for Markets quote rows.
  final bool showInvestInterest;

  /// Sparkles control that deep-links into Investigate for this symbol.
  final bool showInvestigate;

  /// Optional You/Agent chip (Invest interest pane).
  final String? sourceLabel;

  /// When [sourceLabel] is set, styles Agent with primary and You muted.
  final bool sourceIsAgent;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final priceFormat = context.select<DisplaySettings, PriceFormat>(
      (d) => d.priceFormat,
    );
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

    final favorited = showFavorite &&
        context.select<FavoritesRepository, bool>(
          (f) => f.isFavorite(quote.symbol),
        );
    final investMarked = showInvestInterest &&
        context.select<FavoritesRepository, bool>(
          (f) => f.isInvestInterest(quote.symbol),
        );

    final favoriteButton = showFavorite
        ? _FavoriteStarButton(
            symbol: quote.symbol,
            compact: compact,
            favorited: favorited,
          )
        : null;
    final investInterestButton = showInvestInterest
        ? _InvestInterestButton(
            symbol: quote.symbol,
            compact: compact,
            marked: investMarked,
          )
        : null;
    final isCryptoRow = cryptoExchangeId != null;
    final launchIntent = isCryptoRow
        ? AgentLaunchIntent.explainCryptoSpot
        : AgentLaunchIntent.investigate;
    final investigateButton = showInvestigate
        ? AgentLaunchButton(
            symbol: quote.symbol,
            intent: launchIntent,
            exchangeId: cryptoExchangeId,
            iconOnly: true,
          )
        : null;

    final overflowActions = <OverflowAction>[
      if (showInvestigate) ...[
        if (isCryptoRow)
          OverflowAction(
            label: AgentLaunchIntent.explainCryptoSpot.ctaLabel,
            icon: LucideIcons.bitcoin,
            onTap: () {
              AgentLaunchActions.launch(
                context,
                intent: AgentLaunchIntent.explainCryptoSpot,
                symbol: quote.symbol,
                exchangeId: cryptoExchangeId,
              );
            },
          ),
        OverflowAction(
          label: AgentLaunchIntent.investigate.ctaLabel,
          icon: LucideIcons.sparkles,
          onTap: () {
            AgentLaunchActions.launch(
              context,
              intent: AgentLaunchIntent.investigate,
              symbol: quote.symbol,
            );
          },
        ),
        OverflowAction(
          label: AgentLaunchIntent.tradeCheck.ctaLabel,
          icon: LucideIcons.candlestickChart,
          onTap: () {
            AgentLaunchActions.launch(
              context,
              intent: AgentLaunchIntent.tradeCheck,
              symbol: quote.symbol,
            );
          },
        ),
      ],
      if (showInvestInterest)
        OverflowAction(
          label: investMarked
              ? 'Remove from invest interest'
              : 'Add to invest interest',
          icon: LucideIcons.crosshair,
          active: investMarked,
          onTap: () {
            context.read<FavoritesRepository>().toggleInvestInterest(
                  quote.symbol,
                );
          },
        ),
      if (showFavorite)
        OverflowAction(
          label: favorited ? 'Remove from favorites' : 'Add to favorites',
          icon: favorited ? LucideIcons.star : LucideIcons.starOff,
          active: favorited,
          onTap: () {
            context.read<FavoritesRepository>().toggleFavorite(quote.symbol);
          },
        ),
    ];

    final sourceChip = sourceLabel == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: sourceIsAgent
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : theme.colorScheme.secondary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: sourceIsAgent
                    ? theme.colorScheme.primary.withValues(alpha: 0.35)
                    : theme.colorScheme.border,
              ),
            ),
            child: Text(
              sourceLabel!,
              style: theme.textTheme.small.copyWith(
                color: sourceIsAgent
                    ? theme.colorScheme.primary
                    : theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          );

    final leading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: AppEllipsisText(
                quote.symbol,
                maxLines: 2,
                style: theme.textTheme.large,
              ),
            ),
            if (sourceChip != null) ...[
              const SizedBox(width: 6),
              sourceChip,
            ],
          ],
        ),
        if (subtitle != null) ...[
          SizedBox(height: compact ? 1 : 2),
          AppEllipsisText(
            subtitle,
            maxLines: 2,
            style: theme.textTheme.muted,
          ),
        ],
      ],
    );

    final priceColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppMoneyText(
          priceText,
          style: theme.textTheme.large,
        ),
        SizedBox(height: compact ? 1 : 2),
        AppMoneyText(
          changeText,
          style: theme.textTheme.small.copyWith(color: changeColor),
        ),
      ],
    );

    final row = TappableNavRow(
      onTap: onTap,
      compact: compact,
      leading: leading,
      trailing: RowActionCluster(
        actions: overflowActions,
        inlineChildren: [
          ?investigateButton,
          ?investInterestButton,
          if (favoriteButton != null) ...[
            favoriteButton,
            SizedBox(width: compact ? 4 : 8),
          ],
        ],
        child: priceColumn,
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
    required this.compact,
    required this.favorited,
  });

  final String symbol;
  final bool compact;
  final bool favorited;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
            context.read<FavoritesRepository>().toggleFavorite(symbol);
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

class _InvestInterestButton extends StatelessWidget {
  const _InvestInterestButton({
    required this.symbol,
    required this.compact,
    required this.marked,
  });

  final String symbol;
  final bool compact;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = marked
        ? 'Remove $symbol from invest interest'
        : 'Add $symbol to invest interest';

    return Semantics(
      button: true,
      label: label,
      child: AppTooltip(
        message: marked
            ? 'Remove from invest interest'
            : 'For agents — assets you want to invest in',
        wrapDetector: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            context.read<FavoritesRepository>().toggleInvestInterest(symbol);
          },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                LucideIcons.crosshair,
                size: compact ? 18 : 20,
                color: marked
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
