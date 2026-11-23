import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/app_copy.dart';
import '../data/agents/agent_launch.dart';
import '../data/crypto/crypto_exchange_registry.dart';
import '../data/market/market_data_client.dart';
import '../data/market/symbol_search_index.dart';
import '../data/portfolio/portfolio_repository.dart';
import '../data/settings/data_source_settings.dart';
import '../data/settings/favorites_repository.dart';
import 'agent_launch_button.dart';
import 'app_dialog.dart';
import 'app_text.dart';
import 'app_tooltip.dart';
import 'tappable_nav_row.dart';

/// Shell search control — opens curated symbol search dialog.
class SymbolSearchButton extends StatelessWidget {
  const SymbolSearchButton({
    super.key,
    required this.onSymbolSelected,
  });

  /// Called after the dialog closes with the chosen symbol.
  final ValueChanged<String> onSymbolSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return AppTooltip(
      message: AppCopy.symbolSearchTooltip,
      wrapDetector: true,
      child: ShadButton.ghost(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        onPressed: () async {
          final symbol = await showSymbolSearch(context);
          if (symbol == null || symbol.isEmpty) return;
          onSymbolSelected(symbol);
        },
        child: Icon(
          LucideIcons.search,
          size: 20,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Shows curated symbol search; returns the selected symbol or null.
Future<String?> showSymbolSearch(BuildContext context) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => const _SymbolSearchDialog(),
  );
}

class _SymbolSearchDialog extends StatefulWidget {
  const _SymbolSearchDialog();

  @override
  State<_SymbolSearchDialog> createState() => _SymbolSearchDialogState();
}

class _SymbolSearchDialogState extends State<_SymbolSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _query = '';
  var _entries = <SymbolSearchEntry>[];
  var _loadingCatalog = true;

  @override
  void initState() {
    super.initState();
    // Focus comes from [showAppDialog]; bootstrap catalog after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final crypto = context.read<CryptoExchangeRegistry>();
    final favorites = context.read<FavoritesRepository>();
    final portfolio = context.read<PortfolioRepository>();
    final dataSources = context.read<DataSourceSettings>();
    final marketData = context.read<MarketDataClient>();

    var entries = buildSymbolSearchEntries(
      cryptoRegistry: crypto,
      favorites: favorites,
      portfolio: portfolio,
      dataSources: dataSources,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loadingCatalog = false;
    });

    final browsed = await mergeCryptoBrowseSymbols(
      cryptoRegistry: crypto,
      dataSources: dataSources,
    );
    if (!mounted) return;
    entries = buildSymbolSearchEntries(
      cryptoRegistry: crypto,
      favorites: favorites,
      portfolio: portfolio,
      dataSources: dataSources,
      extraSymbols: browsed,
    );
    setState(() => _entries = entries);

    final names = await enrichSymbolDisplayNames(
      marketData: marketData,
      symbols: entries.map((e) => e.symbol),
    );
    if (!mounted || names.isEmpty) return;
    setState(() => _entries = applyDisplayNames(entries, names));
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    setState(() => _query = '');
  }

  void _select(String symbol) {
    Navigator.of(context).pop(symbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final filtered = filterSymbolSearchEntries(_entries, _query);
    final hasQuery = _controller.text.trim().isNotEmpty;
    final showEmptyHint = !_loadingCatalog && _query.trim().isEmpty;
    final showNoMatches =
        !_loadingCatalog && _query.trim().isNotEmpty && filtered.isEmpty;

    return ShadDialog(
      constraints: BoxConstraints(
        maxWidth: wide ? 440 : MediaQuery.sizeOf(context).width - 32,
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      title: const Text('Search'),
      description: Text(
        AppCopy.symbolSearchEmpty,
        style: theme.textTheme.muted,
      ),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: ShadInput(
              controller: _controller,
              autofocus: true,
              placeholder: const Text(AppCopy.symbolSearchHint),
              onChanged: _onQueryChanged,
              leading: Icon(
                LucideIcons.search,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
              trailing: hasQuery
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _clear,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Icon(
                            LucideIcons.x,
                            size: 16,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingCatalog)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: ShadProgress()),
            )
          else if (showEmptyHint)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                AppCopy.symbolSearchEmpty,
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
            )
          else if (showNoMatches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                AppCopy.symbolSearchNoMatches,
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  return _SymbolSearchRow(
                    entry: entry,
                    onTap: () => _select(entry.symbol),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SymbolSearchRow extends StatelessWidget {
  const _SymbolSearchRow({
    required this.entry,
    required this.onTap,
  });

  final SymbolSearchEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final subtitleBits = <String>[
      if (entry.name != null &&
          entry.name!.trim().isNotEmpty &&
          entry.name!.toUpperCase() != entry.symbol.toUpperCase())
        entry.name!.trim(),
      if (entry.kindLabel != null && entry.kindLabel!.trim().isNotEmpty)
        entry.kindLabel!.trim(),
    ];
    final subtitle = subtitleBits.isEmpty ? null : subtitleBits.join(' · ');

    return TappableNavRow(
      compact: true,
      onTap: onTap,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppEllipsisText(
            entry.symbol,
            style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            AppEllipsisText(
              subtitle,
              style: theme.textTheme.muted,
              maxLines: 1,
            ),
          ],
        ],
      ),
      trailing: AgentLaunchButton(
        symbol: entry.symbol,
        intent: AgentLaunchIntent.investigate,
        iconOnly: true,
        // Launch while providers are still available, then dismiss search.
        afterLaunch: () {
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
