import 'package:flutter/foundation.dart';

/// Bottom-tab selection for [HomeShell], including deep-links from feature CTAs.
class ShellNavigationController extends ChangeNotifier {
  static const marketsTabIndex = 0;
  static const cryptoTabIndex = 1;
  static const portfolioTabIndex = 2;
  static const agentsTabIndex = 3;
  static const settingsTabIndex = 4;

  var _tabIndex = marketsTabIndex;
  String? _pendingAgentConnectRoleId;
  var _pendingOpenAgentActivity = false;
  String? _pendingSettingsSectionId;

  int get tabIndex => _tabIndex;

  /// Role id to open Connect for once the Agents tab is visible; cleared by
  /// [takePendingAgentConnectRoleId].
  String? get pendingAgentConnectRoleId => _pendingAgentConnectRoleId;

  /// When true, Agents tab should highlight the Activity pane.
  bool get pendingOpenAgentActivity => _pendingOpenAgentActivity;

  String? get pendingSettingsSectionId => _pendingSettingsSectionId;

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
}
