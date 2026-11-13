import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/in_tab_back.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/nav_back_button.dart';
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
    VoidCallback? systemBack;
    if (_narrowSelected != null) {
      systemBack = _backToSectionList;
    } else if (widget.showGroupBack) {
      systemBack = widget.onGroupBack;
    }

    return InTabBackEffect(
      onBack: systemBack,
      child: LayoutBuilder(
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
                      widget.showGroupBack ? 12 : 20,
                      8,
                      20,
                      12,
                    ),
                    child: widget.showGroupBack
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: NavBackButton(
                                  label: 'Crypto',
                                  onPressed: widget.onGroupBack,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(exchangeName, style: theme.textTheme.h4),
                              const SizedBox(height: 4),
                              Text(
                                'Favorites and spot pairs for this venue.',
                                style: theme.textTheme.small.copyWith(
                                  color: theme.colorScheme.mutedForeground,
                                ),
                              ),
                            ],
                          )
                        : Column(
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
                ),
              Expanded(
                child: MasterDetailShell<CryptoExchangeSection>(
                  selected: _selected,
                  narrowSelected: _narrowSelected,
                  onNarrowBack: _backToSectionList,
                  sidebarWidth: 200,
                  sidebarBuilder: (context, highlighted, {required wide}) {
                    return MasterDetailNavList(
                      tiles: [
                        for (final section in CryptoExchangeSection.values)
                          MasterDetailNavTile(
                            title: section.title,
                            meta: _metaFor(section, favorites),
                            icon: section.icon,
                            selected: highlighted == section,
                            onTap: () => _select(section, wide: wide),
                          ),
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
                          backLabel: exchangeName,
                        ),
                      CryptoExchangeSection.pairs => CryptoExchangePairsPane(
                          key: ValueKey(
                            'pairs-${widget.client.exchange.id}',
                          ),
                          client: widget.client,
                          showBack: showBack,
                          onBack: onBack,
                          backLabel: exchangeName,
                        ),
                    };
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
