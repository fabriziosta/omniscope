import '../core/material_compat.dart'
    show ReorderableDragStartListener, ReorderableListView;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/app_copy.dart';
import '../core/fade_page_route.dart';
import '../data/market/market_data_client.dart';
import '../data/settings/display_settings.dart';
import '../features/asset_detail/asset_detail_screen.dart';
import '../features/quotes/quotes_list_controller.dart';
import 'app_empty_view.dart';
import 'master_detail_shell.dart';
import 'quote_list_tile.dart';
import 'quotes_async_body.dart';

/// Shared Favorites content pane for Markets.
///
/// [onReorder] should persist the new order and return the updated symbol list
/// so the [QuotesListController] can stay in sync without remounting.
class FavoritesQuotesPane extends StatelessWidget {
  const FavoritesQuotesPane({
    super.key,
    required this.symbols,
    required this.subtitle,
    required this.emptyMessage,
    required this.onReorder,
    required this.onOpenMenu,
    this.blockedMessage,
    this.title = 'Favorites',
    this.errorTitle = 'Could not load Favorites',
    this.sourceLabelFor,
    this.sourceIsAgentFor,
    this.onClearAll,
    this.clearAllLabel = 'Clear all',
  });

  final List<String> symbols;
  final String subtitle;
  final String emptyMessage;
  final Future<List<String>> Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onOpenMenu;

  /// When non-null (e.g. no data sources enabled), shown instead of the list.
  final String? blockedMessage;

  final String title;
  final String errorTitle;

  /// Optional You/Agent label per symbol (Invest interest pane).
  final String? Function(String symbol)? sourceLabelFor;

  /// When [sourceLabelFor] is set, whether the chip uses Agent styling.
  final bool Function(String symbol)? sourceIsAgentFor;

  /// Clears the whole list (shown in the content pane trailing when non-empty).
  final VoidCallback? onClearAll;

  final String clearAllLabel;

  @override
  Widget build(BuildContext context) {
    final membershipKey = ([...symbols]..sort()).join('|');
    return ChangeNotifierProvider(
      key: ValueKey(membershipKey),
      create: (context) => QuotesListController(
        client: context.read<MarketDataClient>(),
        symbols: symbols,
        errorTitle: errorTitle,
      )..refresh(),
      child: _FavoritesQuotesPaneView(
        title: title,
        errorTitle: errorTitle,
        symbols: symbols,
        subtitle: subtitle,
        emptyMessage: emptyMessage,
        onReorder: onReorder,
        onOpenMenu: onOpenMenu,
        blockedMessage: blockedMessage,
        sourceLabelFor: sourceLabelFor,
        sourceIsAgentFor: sourceIsAgentFor,
        onClearAll: onClearAll,
        clearAllLabel: clearAllLabel,
      ),
    );
  }
}

class _FavoritesQuotesPaneView extends StatelessWidget {
  const _FavoritesQuotesPaneView({
    required this.title,
    required this.errorTitle,
    required this.symbols,
    required this.subtitle,
    required this.emptyMessage,
    required this.onReorder,
    required this.onOpenMenu,
    this.blockedMessage,
    this.sourceLabelFor,
    this.sourceIsAgentFor,
    this.onClearAll,
    this.clearAllLabel = 'Clear all',
  });

  final String title;
  final String errorTitle;
  final List<String> symbols;
  final String subtitle;
  final String emptyMessage;
  final Future<List<String>> Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onOpenMenu;
  final String? blockedMessage;
  final String? Function(String symbol)? sourceLabelFor;
  final bool Function(String symbol)? sourceIsAgentFor;
  final VoidCallback? onClearAll;
  final String clearAllLabel;

  void _openAsset(BuildContext context, String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final density = context.watch<DisplaySettings>().listDensity;
    final gap = density == ListDensity.compact ? 4.0 : 8.0;
    final blocked = blockedMessage;
    final showClear = onClearAll != null &&
        blocked == null &&
        symbols.isNotEmpty;

    return MasterDetailContentPane(
      title: title,
      subtitle: subtitle,
      onOpenMenu: onOpenMenu,
      trailing: showClear
          ? ShadButton.outline(
              size: ShadButtonSize.sm,
              height: 44,
              onPressed: onClearAll,
              child: Text(clearAllLabel),
            )
          : null,
      body: blocked != null
          ? AppEmptyView(blocked)
          : symbols.isEmpty
              ? AppEmptyView(emptyMessage)
              : QuotesAsyncBody(
                  errorTitle: errorTitle,
                  builder: (context, quotes) {
                    if (quotes.isEmpty) {
                      return const AppEmptyView(AppCopy.noQuotes);
                    }
                    final bySymbol = {for (final q in quotes) q.symbol: q};
                    final ordered = [
                      for (final s in symbols)
                        if (bySymbol.containsKey(s)) bySymbol[s]!,
                    ];
                    return ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: ordered.length,
                      onReorderItem: (oldIndex, newIndex) async {
                        final next = await onReorder(oldIndex, newIndex);
                        if (!context.mounted) return;
                        context
                            .read<QuotesListController>()
                            .updateSymbols(next);
                      },
                      itemBuilder: (context, index) {
                        final quote = ordered[index];
                        return Padding(
                          key: ValueKey(quote.symbol),
                          padding: EdgeInsets.only(
                            bottom: index < ordered.length - 1 ? gap : 0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: QuoteListTile(
                                  quote: quote,
                                  density: density,
                                  onTap: () =>
                                      _openAsset(context, quote.symbol),
                                  sourceLabel:
                                      sourceLabelFor?.call(quote.symbol),
                                  sourceIsAgent: sourceIsAgentFor?.call(
                                        quote.symbol,
                                      ) ??
                                      false,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    LucideIcons.gripVertical,
                                    size: 18,
                                    color: ShadTheme.of(context)
                                        .colorScheme
                                        .mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
