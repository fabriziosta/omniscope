import '../settings/config_list_repository.dart';
import '../settings/user_config_keys.dart';
import 'trade_proposal.dart';

class TradeProposalRepository extends ConfigListRepository<TradeProposal> {
  TradeProposalRepository({super.store})
      : super(
          sliceKey: UserConfigKeys.tradeProposals,
          listKey: 'proposals',
          maxStored: 200,
          idOf: (p) => p.id,
          fromJson: (json) {
            final p = TradeProposal.fromJson(json);
            return p.id.isNotEmpty ? p : null;
          },
          toJson: (p) => p.toJson(),
        );

  List<TradeProposal> get proposals => items;

  List<TradeProposal> pendingForRole(String roleId) => [
        for (final p in items)
          if (p.roleId == roleId && p.status == TradeProposalStatus.pending) p,
      ];

  /// Pending buy/sell proposals that still need Confirm (excludes holds).
  List<TradeProposal> get pendingActionable => [
        for (final p in items)
          if (p.status == TradeProposalStatus.pending &&
              p.side != TradeProposalSide.hold &&
              p.quantity > 0)
            p,
      ];

  int get pendingActionableCount => pendingActionable.length;

  TradeProposal? byId(String id) {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  TradeProposal? bySourceMessageId(String messageId) {
    for (final p in items) {
      if (p.sourceMessageId == messageId) return p;
    }
    return null;
  }

  List<TradeProposal> forChat(String chatId) {
    final id = chatId.trim();
    return [
      for (final p in items)
        if (p.chatId == id) p,
    ];
  }

  List<TradeProposal> executedForSymbol(String symbol) {
    final sym = symbol.trim().toUpperCase();
    return [
      for (final p in items)
        if (p.status == TradeProposalStatus.executed && p.symbol == sym) p,
    ];
  }
}
