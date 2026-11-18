import '../settings/favorites_repository.dart';
import '../settings/mandate_settings.dart';
import 'agent_activity.dart';
import 'agent_activity_repository.dart';
import 'invest_interest_proposal.dart';
import 'invest_interest_proposal_repository.dart';

/// Confirm / Dismiss / Autopilot for agent Invest interest diffs.
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
  Future<String?> confirm(String proposalId, {bool autopilot = false}) async {
    final proposal = _proposals.byId(proposalId);
    if (proposal == null) return 'Proposal not found.';
    if (proposal.status != InvestInterestProposalStatus.pending) {
      return 'This proposal is no longer pending.';
    }
    if (!proposal.isActionable) {
      return 'Nothing to apply in this proposal.';
    }

    if (autopilot && !isAutopilotAddOnlyEligible(proposal)) {
      return 'Autopilot only applies add-only Invest interest proposals.';
    }

    try {
      if (autopilot) {
        await _applyAddOnly(proposal);
      } else if (proposal.setSymbols != null) {
        final next = _capUnique(proposal.setSymbols!, _mandate.maxSymbolCount);
        await _favorites.applyInvestInterest(
          next,
          managedByRoleId: proposal.roleId,
        );
      } else {
        await _applyAddRemove(proposal);
      }

      await _proposals.upsert(
        proposal.copyWith(
          status: InvestInterestProposalStatus.confirmed,
          clearApplyError: true,
        ),
      );
      await _activity.add(
        AgentActivityEvent(
          id: AgentActivityEvent.newId(),
          kind: autopilot
              ? AgentActivityKind.autopilotInvestInterestApplied
              : AgentActivityKind.investInterestConfirmed,
          roleId: proposal.roleId,
          createdAt: DateTime.now().toUtc(),
          proposalId: proposal.id,
          summary: autopilot
              ? 'Autopilot · ${proposal.summaryLabel}'
              : 'Confirmed invest interest · ${proposal.summaryLabel}',
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

  /// True when Autopilot may auto-apply: investigation II roles, add-only.
  static bool isAutopilotAddOnlyEligible(InvestInterestProposal proposal) {
    if (!supportsInvestigationAutopilot(proposal.roleId)) return false;
    if (proposal.setSymbols != null) return false;
    if (proposal.remove.isNotEmpty) return false;
    return proposal.add.isNotEmpty;
  }

  /// Investigation roles that may Autopilot-apply Invest interest adds.
  static bool supportsInvestigationAutopilot(String roleId) {
    return roleId == 'marketResearch' || roleId == 'portfolioGuide';
  }

  Future<void> _applyAddOnly(InvestInterestProposal proposal) async {
    final maxSymbols = _mandate.maxSymbolCount;
    final currentCount = _favorites.investInterestSymbols.length;
    final room = maxSymbols - currentCount;
    if (room <= 0) return;
    final toAdd = _capUnique(proposal.add, room);
    if (toAdd.isEmpty) return;
    await _favorites.applyInvestInterestDiff(
      add: toAdd,
      managedByRoleId: proposal.roleId,
    );
  }

  Future<void> _applyAddRemove(InvestInterestProposal proposal) async {
    final maxSymbols = _mandate.maxSymbolCount;
    final remove = _normalizeList(proposal.remove);
    final current = List<String>.from(_favorites.investInterestSymbols);
    final kept = [
      for (final s in current)
        if (!remove.contains(s.trim().toUpperCase())) s,
    ];
    final room = maxSymbols - kept.length;
    final toAdd = room > 0 ? _capUnique(proposal.add, room) : <String>[];
    await _favorites.applyInvestInterestDiff(
      add: toAdd,
      remove: remove,
      managedByRoleId: proposal.roleId,
    );
  }

  static List<String> _normalizeList(List<String> symbols) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in symbols) {
      final s = raw.trim().toUpperCase();
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
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
