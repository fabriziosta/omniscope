import '../settings/config_list_repository.dart';
import '../settings/user_config_keys.dart';
import '../settings/user_config_store.dart';
import 'invest_interest_proposal.dart';

class InvestInterestProposalRepository
    extends ConfigListRepository<InvestInterestProposal> {
  InvestInterestProposalRepository({UserConfigStore? store})
      : super(
          store: store,
          sliceKey: UserConfigKeys.investInterestProposals,
          listKey: 'proposals',
          maxStored: 200,
          idOf: (p) => p.id,
          fromJson: (json) {
            final p = InvestInterestProposal.fromJson(json);
            return p.id.isNotEmpty ? p : null;
          },
          toJson: (p) => p.toJson(),
        );

  List<InvestInterestProposal> get proposals => items;

  List<InvestInterestProposal> pendingForRole(String roleId) => [
        for (final p in items)
          if (p.roleId == roleId &&
              p.status == InvestInterestProposalStatus.pending)
            p,
      ];

  List<InvestInterestProposal> get pendingActionable => [
        for (final p in items)
          if (p.isActionable) p,
      ];

  int get pendingActionableCount => pendingActionable.length;

  InvestInterestProposal? byId(String id) {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  InvestInterestProposal? bySourceMessageId(String messageId) {
    for (final p in items) {
      if (p.sourceMessageId == messageId) return p;
    }
    return null;
  }
}
