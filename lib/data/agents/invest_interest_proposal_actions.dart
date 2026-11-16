import '../settings/favorites_repository.dart';
import '../settings/mandate_settings.dart';
import 'agent_activity.dart';
import 'agent_activity_repository.dart';
import 'invest_interest_proposal.dart';
import 'invest_interest_proposal_repository.dart';

/// Confirm / Dismiss for agent Invest interest diffs.
class InvestInterestProposalActions {
  InvestInterestProposalActions({
    required this._proposals,
    required this._activity,
    required this._favorites,
    required this._mandate,
  });

  final InvestInterestProposalRepository _proposals;
  final AgentActivityRepository _activity;
  final FavoritesRepository _favorites;
  final MandateSettings _mandate;

  /// Apply a pending proposal to Markets → Invest interest.
  Future<String?> confirm(String proposalId) async {
    final proposal = _proposals.byId(proposalId);
    if (proposal == null) return 'Proposal not found.';
    if (proposal.status != InvestInterestProposalStatus.pending) {
      return 'This proposal is no longer pending.';
    }
    if (!proposal.isActionable) {
      return 'Nothing to apply in this proposal.';
    }

    try {
      final next = _resolveNextList(proposal);
      await _favorites.applyInvestInterest(
        next,
        managedByRoleId: proposal.roleId,
      );
      await _proposals.upsert(
        proposal.copyWith(
          status: InvestInterestProposalStatus.confirmed,
          clearApplyError: true,
        ),
      );
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: AgentActivityKind.investInterestConfirmed,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          proposalId: proposal.id,
          summary: 'Confirmed invest interest · ${proposal.summaryLabel}',
        ),
      );
      return null;
    } catch (e) {
      final err = e.toString();
      await _proposals.upsert(
        proposal.copyWith(
          status: InvestInterestProposalStatus.failed,
          applyError: err,
        ),
      );
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: AgentActivityKind.investInterestFailed,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          proposalId: proposal.id,
          summary: err,
        ),
      );
      return err;
    }
  }

  Future<String?> dismiss(String proposalId) async {
    final proposal = _proposals.byId(proposalId);
    if (proposal == null) return 'Proposal not found.';
    if (proposal.status != InvestInterestProposalStatus.pending) {
      return 'This proposal is no longer pending.';
    }
    await _proposals.upsert(
      proposal.copyWith(status: InvestInterestProposalStatus.dismissed),
    );
    await _activity.add(
      AgentActivityEvent(
        id: AgentActivityEvent.newId(),
        kind: AgentActivityKind.investInterestDismissed,
        roleId: proposal.roleId,
        createdAt: DateTime.now().toUtc(),
        proposalId: proposal.id,
        summary: 'Dismissed invest interest · ${proposal.summaryLabel}',
      ),
    );
    return null;
  }

  List<String> _resolveNextList(InvestInterestProposal proposal) {
    final maxSymbols = _mandate.maxSymbolCount;
    if (proposal.setSymbols != null) {
      return _capUnique(proposal.setSymbols!, maxSymbols);
    }
    final current = List<String>.from(_favorites.investInterestSymbols);
    final remove = {for (final s in proposal.remove) s.trim().toUpperCase()};
    final kept = [
      for (final s in current)
        if (!remove.contains(s.trim().toUpperCase())) s,
    ];
    final seen = {for (final s in kept) s.trim().toUpperCase()};
    for (final raw in proposal.add) {
      final s = raw.trim().toUpperCase();
      if (s.isEmpty || seen.contains(s)) continue;
      kept.add(s);
      seen.add(s);
    }
    return _capUnique(kept, maxSymbols);
  }

  static List<String> _capUnique(List<String> symbols, int maxSymbols) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in symbols) {
      final s = raw.trim().toUpperCase();
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
      if (out.length >= maxSymbols) break;
    }
    return out;
  }
}
