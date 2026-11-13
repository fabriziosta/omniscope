import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/app_copy.dart';
import '../../data/crypto/crypto_exchange_client.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/settings/data_source_settings.dart';
import '../../data/settings/favorites_repository.dart';
import '../../widgets/app_empty_view.dart';
import '../../widgets/master_detail_shell.dart';
import '../../widgets/tab_page_header.dart';
import 'crypto_exchange_hub.dart';

/// Crypto group — registered exchanges via size-aware master–detail.
class CryptoGroupScreen extends StatefulWidget {
  const CryptoGroupScreen({super.key});

  @override
  State<CryptoGroupScreen> createState() => _CryptoGroupScreenState();
}

class _CryptoGroupScreenState extends State<CryptoGroupScreen> {
  /// Stable exchange id for wide selection.
  String? _selectedId;
  String? _narrowSelectedId;

  void _select(String exchangeId, {required bool wide}) {
    setState(() {
      _selectedId = exchangeId;
      if (!wide) {
        _narrowSelectedId = exchangeId;
      }
    });
  }

  void _backToNavList() {
    setState(() => _narrowSelectedId = null);
  }

  CryptoExchangeClient? _clientById(
    List<CryptoExchangeClient> exchanges,
    String? id,
  ) {
    if (id == null) return null;
    for (final client in exchanges) {
      if (client.exchange.id == id) return client;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<CryptoExchangeRegistry>();
    final dataSources = context.watch<DataSourceSettings>();
    final favorites = context.watch<FavoritesRepository>();
    final exchanges = registry.enabledWhere(dataSources.isCryptoEnabled);

    final wideSelected = _clientById(exchanges, _selectedId) ??
        (exchanges.isEmpty ? null : exchanges.first);
    final narrowSelected = _clientById(exchanges, _narrowSelectedId);

    final emptyMessage = registry.exchanges.isEmpty
        ? AppCopy.noCryptoExchangesRegistered
        : AppCopy.noCryptoExchangesEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabPageHeader(
          title: 'Crypto',
          subtitle: 'Spot markets by exchange. Pick a venue to browse pairs.',
        ),
        Expanded(
          child: exchanges.isEmpty || wideSelected == null
              ? AppEmptyView(emptyMessage)
              : MasterDetailShell<CryptoExchangeClient>(
                  selected: wideSelected,
                  narrowSelected: narrowSelected,
                  onNarrowBack: _backToNavList,
                  sidebarBuilder: (context, highlighted, {required wide}) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        for (var i = 0; i < exchanges.length; i++) ...[
                          if (i > 0) const SizedBox(height: 6),
                          MasterDetailNavTile(
                            title: exchanges[i].exchange.displayName,
                            meta: () {
                              final id = exchanges[i].exchange.id;
                              final favCount =
                                  favorites.cryptoSymbolsFor(id).length;
                              if (favCount == 0) return 'Spot pairs';
                              return favCount == 1
                                  ? 'Spot pairs · 1 favorite'
                                  : 'Spot pairs · $favCount favorites';
                            }(),
                            icon: LucideIcons.bitcoin,
                            selected: highlighted?.exchange.id ==
                                exchanges[i].exchange.id,
                            onTap: () => _select(
                              exchanges[i].exchange.id,
                              wide: wide,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  contentBuilder:
                      (context, client, {required showBack, onBack}) {
                    return CryptoExchangeHub(
                      key: ValueKey(client.exchange.id),
                      client: client,
                      showGroupBack: showBack,
                      onGroupBack: onBack,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
