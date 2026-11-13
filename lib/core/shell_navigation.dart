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
  static const agentsTabIndex = 2;
  static const settingsTabIndex = 3;

  var _tabIndex = marketsTabIndex;
  String? _pendingAgentConnectRoleId;
  var _pendingOpenAgentActivity = false;
  String? _pendingSettingsSectionId;
  PendingAgentChatOpen? _pendingAgentChatOpen;

  int get tabIndex => _tabIndex;

  /// Role id to open Connect for once the Agents tab is visible; cleared by
  /// [takePendingAgentConnectRoleId].
  String? get pendingAgentConnectRoleId => _pendingAgentConnectRoleId;

  /// When true, Agents tab should highlight the Activity pane.
  bool get pendingOpenAgentActivity => _pendingOpenAgentActivity;

  String? get pendingSettingsSectionId => _pendingSettingsSectionId;

  PendingAgentChatOpen? get pendingAgentChatOpen => _pendingAgentChatOpen;

  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Switch to Agents and optionally queue a Connect dialog for [connectRoleId].
  void goToAgents({String? connectRoleId, bool openActivity = false}) {
    _pendingAgentConnectRoleId = connectRoleId;
    _pendingOpenAgentActivity = openActivity;
    _tabIndex = agentsTabIndex;
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

  bool takePendingOpenAgentActivity() {
    final v = _pendingOpenAgentActivity;
    _pendingOpenAgentActivity = false;
    return v;
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
