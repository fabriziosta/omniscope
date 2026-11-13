import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/master_detail_shell.dart';
import 'crypto_exchange_favorites_body.dart';
import 'crypto_exchange_pairs_body.dart';

enum CryptoExchangeSection {
  favorites,
  pairs,
}

extension CryptoExchangeSectionX on CryptoExchangeSection {
  String get title => switch (this) {
        CryptoExchangeSection.favorites => 'Favorites',
        CryptoExchangeSection.pairs => 'Spot pairs',
      };

  IconData get icon => switch (this) {
        CryptoExchangeSection.favorites => LucideIcons.star,
        CryptoExchangeSection.pairs => LucideIcons.chartCandlestick,
      };
}

/// Nested master–detail for one exchange: Favorites | Spot pairs.
///
/// Used as the content pane of [CryptoGroupScreen]. Narrow Back returns to
/// the exchange section list (not the Crypto group list); the group shell
/// owns group-level Back separately via [showGroupBack].
class CryptoExchangeHub extends StatefulWidget {
  const CryptoExchangeHub({
    super.key,
    required this.client,
    required this.showGroupBack,
    this.onGroupBack,
  });

  final CryptoExchangeClient client;
  final bool showGroupBack;
  final VoidCallback? onGroupBack;

  @override
  State<CryptoExchangeHub> createState() => _CryptoExchangeHubState();
}

class _CryptoExchangeHubState extends State<CryptoExchangeHub> {
  CryptoExchangeSection _selected = CryptoExchangeSection.pairs;
  CryptoExchangeSection? _narrowSelected;

  void _select(CryptoExchangeSection section, {required bool wide}) {
    setState(() {
      _selected = section;
      if (!wide) {
        _narrowSelected = section;
      }
    });
  }

  void _backToSectionList() {
    setState(() => _narrowSelected = null);
  }

  String _metaFor(
    CryptoExchangeSection section,
    FavoritesRepository favorites,
  ) {
    if (section == CryptoExchangeSection.favorites) {
      final count =
          favorites.cryptoSymbolsFor(widget.client.exchange.id).length;
      return count == 1 ? '1 pair' : '$count pairs';
    }
    return 'Browse instruments';
  }

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesRepository>();
    final theme = ShadTheme.of(context);
    final exchangeName = widget.client.exchange.displayName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final nestedWide = constraints.maxWidth >=
            MasterDetailShell.wideBreakpointDefault;
        // On narrow, hide exchange chrome while a section pane is open so
        // only one Back control is visible (section → hub → group).
        final showHubHeader = nestedWide || _narrowSelected == null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHubHeader)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.border),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.showGroupBack ? 8 : 20,
                    8,
                    20,
                    12,
                  ),
                  child: Row(
                    children: [
                      if (widget.showGroupBack) ...[
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          onPressed: widget.onGroupBack,
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(exchangeName, style: theme.textTheme.h4),
                            const SizedBox(height: 4),
                            Text(
                              'Favorites and spot pairs for this venue.',
                              style: theme.textTheme.small.copyWith(
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: MasterDetailShell<CryptoExchangeSection>(
                selected: _selected,
                narrowSelected: _narrowSelected,
                onNarrowBack: _backToSectionList,
                sidebarWidth: 200,
                sidebarBuilder: (context, highlighted, {required wide}) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      for (var i = 0;
                          i < CryptoExchangeSection.values.length;
                          i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        MasterDetailNavTile(
                          title: CryptoExchangeSection.values[i].title,
                          meta: _metaFor(
                            CryptoExchangeSection.values[i],
                            favorites,
                          ),
                          icon: CryptoExchangeSection.values[i].icon,
                          selected: highlighted ==
                              CryptoExchangeSection.values[i],
                          onTap: () => _select(
                            CryptoExchangeSection.values[i],
                            wide: wide,
                          ),
                        ),
                      ],
                    ],
                  );
                },
                contentBuilder:
                    (context, section, {required showBack, onBack}) {
                  return switch (section) {
                    CryptoExchangeSection.favorites =>
                      CryptoExchangeFavoritesPane(
                        key: ValueKey(
                          'fav-${widget.client.exchange.id}',
                        ),
                        client: widget.client,
                        showBack: showBack,
                        onBack: onBack,
                      ),
                    CryptoExchangeSection.pairs => CryptoExchangePairsPane(
                        key: ValueKey(
                          'pairs-${widget.client.exchange.id}',
                        ),
                        client: widget.client,
                        showBack: showBack,
                        onBack: onBack,
                      ),
                  };
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
