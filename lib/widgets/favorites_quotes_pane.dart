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
import 'quotes_refresh_body.dart';

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
    required this.showBack,
    this.onBack,
    this.backLabel = 'Back',
    this.blockedMessage,
  });

  final List<String> symbols;
  final String subtitle;
  final String emptyMessage;
  final Future<List<String>> Function(int oldIndex, int newIndex) onReorder;
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;

  /// When non-null (e.g. no data sources enabled), shown instead of the list.
  final String? blockedMessage;

  @override
  Widget build(BuildContext context) {
    final membershipKey = ([...symbols]..sort()).join('|');
    return ChangeNotifierProvider(
      key: ValueKey(membershipKey),
      create: (context) => QuotesListController(
        client: context.read<MarketDataClient>(),
        symbols: symbols,
        errorTitle: 'Could not load Favorites',
      )..refresh(),
      child: _FavoritesQuotesPaneView(
        symbols: symbols,
        subtitle: subtitle,
        emptyMessage: emptyMessage,
        onReorder: onReorder,
        showBack: showBack,
        onBack: onBack,
        backLabel: backLabel,
        blockedMessage: blockedMessage,
      ),
    );
  }
}

class _FavoritesQuotesPaneView extends StatelessWidget {
  const _FavoritesQuotesPaneView({
    required this.symbols,
    required this.subtitle,
    required this.emptyMessage,
    required this.onReorder,
    required this.showBack,
    required this.backLabel,
    this.onBack,
    this.blockedMessage,
  });

  final List<String> symbols;
  final String subtitle;
  final String emptyMessage;
  final Future<List<String>> Function(int oldIndex, int newIndex) onReorder;
  final bool showBack;
  final VoidCallback? onBack;
  final String backLabel;
  final String? blockedMessage;

  void _openAsset(BuildContext context, String symbol) {
    pushFadePage(context, AssetDetailScreen(symbol: symbol));
  }

  @override
  Widget build(BuildContext context) {
    final density = context.watch<DisplaySettings>().listDensity;
    final gap = density == ListDensity.compact ? 6.0 : 10.0;
    final controller = context.watch<QuotesListController>();
    final blocked = blockedMessage;

    return MasterDetailContentPane(
      title: 'Favorites',
      subtitle: subtitle,
      showBack: showBack,
      onBack: onBack,
      backLabel: backLabel,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        enabled: blocked == null &&
            symbols.isNotEmpty &&
            !controller.loading &&
            !controller.loadingMore,
        onPressed: controller.refresh,
        child: const Text('Refresh'),
      ),
      body: blocked != null
          ? AppEmptyView(blocked)
          : symbols.isEmpty
              ? AppEmptyView(emptyMessage)
              : QuotesAsyncBody(
                  errorTitle: 'Could not load Favorites',
                  builder: (context, quotes) {
                    if (quotes.isEmpty) {
                      return const AppEmptyView(AppCopy.noQuotes);
                    }
                    final bySymbol = {for (final q in quotes) q.symbol: q};
                    final ordered = [
                      for (final s in symbols)
                        if (bySymbol.containsKey(s)) bySymbol[s]!,
                    ];
                    return QuotesRefreshBody(
                      child: ReorderableListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
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
                      ),
                    );
                  },
                ),
    );
  }
}
