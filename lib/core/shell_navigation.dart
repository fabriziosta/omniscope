import 'package:flutter/foundation.dart';

/// Queued deep-link to open an agent chat from the shell notification inbox.
class PendingAgentChatOpen {
  const PendingAgentChatOpen({
    required this.roleId,
    this.symbol,
    this.notificationId,
  });

  final String roleId;
  final String? symbol;
  final String? notificationId;
}

/// Bottom-tab selection for [HomeShell], including deep-links from feature CTAs.
class ShellNavigationController extends ChangeNotifier {
  static const marketsTabIndex = 0;
  static const portfolioTabIndex = 1;
  static const activityTabIndex = 2;
  static const agentsTabIndex = 3;
  static const settingsTabIndex = 4;

  var _tabIndex = marketsTabIndex;
  String? _pendingAgentConnectRoleId;
  String? _pendingActivityProposalId;
  String? _pendingSettingsSectionId;
  PendingAgentChatOpen? _pendingAgentChatOpen;

  int get tabIndex => _tabIndex;

  /// Role id to open Connect for once the Agents tab is visible; cleared by
  /// [takePendingAgentConnectRoleId].
  String? get pendingAgentConnectRoleId => _pendingAgentConnectRoleId;

  /// Proposal id to focus on the Activity tab; cleared by
  /// [takePendingActivityProposalId].
  String? get pendingActivityProposalId => _pendingActivityProposalId;

  String? get pendingSettingsSectionId => _pendingSettingsSectionId;

  PendingAgentChatOpen? get pendingAgentChatOpen => _pendingAgentChatOpen;

  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Switch to Agents and optionally queue a Connect dialog for [connectRoleId].
  void goToAgents({String? connectRoleId}) {
    _pendingAgentConnectRoleId = connectRoleId;
    _tabIndex = agentsTabIndex;
    notifyListeners();
  }

  /// Switch to Activity and optionally focus a proposal.
  void goToActivity({String? proposalId}) {
    _pendingActivityProposalId = proposalId;
    _tabIndex = activityTabIndex;
    notifyListeners();
  }

  /// Switch to Agents and open chat for [roleId] (e.g. from a shell notification).
  void goToAgentChat({
    required String roleId,
    String? symbol,
    String? notificationId,
  }) {
    _pendingAgentChatOpen = PendingAgentChatOpen(
      roleId: roleId,
      symbol: symbol,
      notificationId: notificationId,
    );
    _tabIndex = agentsTabIndex;
    notifyListeners();
  }

  void goToSettings({String? sectionId}) {
    _pendingSettingsSectionId = sectionId;
    _tabIndex = settingsTabIndex;
    notifyListeners();
  }

  /// Returns and clears any pending Connect role id.
  String? takePendingAgentConnectRoleId() {
    final id = _pendingAgentConnectRoleId;
    _pendingAgentConnectRoleId = null;
    return id;
  }

  /// Returns and clears any pending Activity proposal focus id.
  String? takePendingActivityProposalId() {
    final id = _pendingActivityProposalId;
    _pendingActivityProposalId = null;
    return id;
  }

  String? takePendingSettingsSectionId() {
    final id = _pendingSettingsSectionId;
    _pendingSettingsSectionId = null;
    return id;
  }

  PendingAgentChatOpen? takePendingAgentChatOpen() {
    final pending = _pendingAgentChatOpen;
    _pendingAgentChatOpen = null;
    return pending;
  }
}
