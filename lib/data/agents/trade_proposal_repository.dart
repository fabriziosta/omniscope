import 'package:flutter/foundation.dart';

import '../settings/config_list_slice.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'trade_proposal.dart';

class TradeProposalRepository extends ChangeNotifier {
  TradeProposalRepository({this.store});

  UserConfigStore? store;
  List<TradeProposal> _proposals = const [];
  bool _ready = false;

  static const maxStored = 200;

  bool get isReady => _ready;
  List<TradeProposal> get proposals => List.unmodifiable(_proposals);

  List<TradeProposal> pendingForRole(String roleId) => [
        for (final p in _proposals)
          if (p.roleId == roleId && p.status == TradeProposalStatus.pending) p,
      ];

  /// Pending buy/sell proposals that still need Confirm (excludes holds).
  List<TradeProposal> get pendingActionable => [
        for (final p in _proposals)
          if (p.status == TradeProposalStatus.pending &&
              p.side != TradeProposalSide.hold &&
              p.quantity > 0)
            p,
      ];

  int get pendingActionableCount => pendingActionable.length;

  TradeProposal? byId(String id) {
    for (final p in _proposals) {
      if (p.id == id) return p;
    }
    return null;
  }

  TradeProposal? bySourceMessageId(String messageId) {
    for (final p in _proposals) {
      if (p.sourceMessageId == messageId) return p;
    }
    return null;
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice = this.store?.getSlice(UserConfigKeys.tradeProposals);
    _proposals = ConfigListSlice.parseItems(
      slice,
      'proposals',
      (json) {
        final p = TradeProposal.fromJson(json);
        return p.id.isNotEmpty ? p : null;
      },
    );
    _ready = true;
    notifyListeners();
  }

  Future<void> upsert(TradeProposal proposal) async {
    _proposals = ConfigListSlice.prependCapped(
      _proposals,
      proposal,
      maxStored: maxStored,
      exclude: (p) => p.id == proposal.id,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _proposals = const [];
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await ConfigListSlice.persist(
      store,
      sliceKey: UserConfigKeys.tradeProposals,
      listKey: 'proposals',
      items: _proposals,
      toJson: (p) => p.toJson(),
    );
  }
}
