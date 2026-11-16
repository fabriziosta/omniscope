import 'package:flutter/foundation.dart';

import '../settings/config_list_slice.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'invest_interest_proposal.dart';

class InvestInterestProposalRepository extends ChangeNotifier {
  InvestInterestProposalRepository({this.store});

  UserConfigStore? store;
  List<InvestInterestProposal> _proposals = const [];
  bool _ready = false;

  static const maxStored = 200;

  bool get isReady => _ready;
  List<InvestInterestProposal> get proposals => List.unmodifiable(_proposals);

  List<InvestInterestProposal> pendingForRole(String roleId) => [
        for (final p in _proposals)
          if (p.roleId == roleId &&
              p.status == InvestInterestProposalStatus.pending)
            p,
      ];

  List<InvestInterestProposal> get pendingActionable => [
        for (final p in _proposals)
          if (p.isActionable) p,
      ];

  int get pendingActionableCount => pendingActionable.length;

  InvestInterestProposal? byId(String id) {
    for (final p in _proposals) {
      if (p.id == id) return p;
    }
    return null;
  }

  InvestInterestProposal? bySourceMessageId(String messageId) {
    for (final p in _proposals) {
      if (p.sourceMessageId == messageId) return p;
    }
    return null;
  }

  Future<void> load({UserConfigStore? store}) async {
    if (store != null) this.store = store;
    final slice =
        this.store?.getSlice(UserConfigKeys.investInterestProposals);
    _proposals = ConfigListSlice.parseItems(
      slice,
      'proposals',
      (json) {
        final p = InvestInterestProposal.fromJson(json);
        return p.id.isNotEmpty ? p : null;
      },
    );
    _ready = true;
    notifyListeners();
  }

  Future<void> upsert(InvestInterestProposal proposal) async {
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
      sliceKey: UserConfigKeys.investInterestProposals,
      listKey: 'proposals',
      items: _proposals,
      toJson: (p) => p.toJson(),
    );
  }
}
