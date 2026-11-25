import 'package:flutter/foundation.dart';

/// Queued deep-link to open an agent chat (Activity Alerts, CTAs).
class PendingAgentChatOpen {
  const PendingAgentChatOpen({
    this.chatId,
    this.symbol,
    this.notificationId,
    this.starterRoleId,
    this.initialExchangeId,
    this.autoRun = false,
    this.initialSide,
    this.initialQuantity,
  });

  final String? chatId;
  final String? symbol;
  final String? notificationId;
  final String? starterRoleId;
  final String? initialExchangeId;
  final bool autoRun;
  final String? initialSide;
  final double? initialQuantity;
}

/// Bottom-tab selection for [HomeShell], including deep-links from feature CTAs.
class ShellNavigationController extends ChangeNotifier {
  /// Portfolio / Home tab (cold start).
  static const homeTabIndex = 0;

  /// Alias for [homeTabIndex] — same tab hosts PortfolioScreen.
  static const portfolioTabIndex = homeTabIndex;

  static const marketsTabIndex = 1;
  static const agentsTabIndex = 2;
  static const activityTabIndex = 3;
  static const settingsTabIndex = 4;

  var _tabIndex = homeTabIndex;
  String? _pendingActivityProposalId;
  var _pendingActivityOpenAlerts = false;
  String? _pendingSettingsSectionId;
  PendingAgentChatOpen? _pendingAgentChatOpen;

  int get tabIndex => _tabIndex;

  String? get pendingActivityProposalId => _pendingActivityProposalId;

  String? get pendingSettingsSectionId => _pendingSettingsSectionId;

  PendingAgentChatOpen? get pendingAgentChatOpen => _pendingAgentChatOpen;

  /// Switch to Home (Portfolio) — brand icon / title and fatal-error "Go home".
  void goToHome() {
    _enterTab(homeTabIndex);
  }

  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Switch to Agents tab.
  void goToAgents() {
    _enterTab(agentsTabIndex);
  }

  void goToActivity({String? proposalId, bool openAlerts = false}) {
    _pendingActivityProposalId = proposalId;
    _pendingActivityOpenAlerts = openAlerts;
    _enterTab(activityTabIndex);
  }

  /// Switch to Agents and open/create a chat (e.g. from Activity Alerts).
  void goToAgentChat({
    String? chatId,
    String? roleId,
    String? symbol,
    String? notificationId,
    String? starterRoleId,
    String? initialExchangeId,
    bool autoRun = false,
    String? initialSide,
    double? initialQuantity,
  }) {
    _pendingAgentChatOpen = PendingAgentChatOpen(
      chatId: chatId,
      symbol: symbol,
      notificationId: notificationId,
      starterRoleId: starterRoleId ?? roleId,
      initialExchangeId: initialExchangeId,
      autoRun: autoRun,
      initialSide: initialSide,
      initialQuantity: initialQuantity,
    );
    _enterTab(agentsTabIndex);
  }

  void goToSettings({String? sectionId}) {
    _pendingSettingsSectionId = sectionId;
    _enterTab(settingsTabIndex);
  }

  void _enterTab(int index) {
    // Always notify so pending deep-link consumers refresh even on same tab.
    _tabIndex = index;
    notifyListeners();
  }

  String? takePendingActivityProposalId() {
    final id = _pendingActivityProposalId;
    _pendingActivityProposalId = null;
    return id;
  }

  bool takePendingActivityOpenAlerts() {
    final open = _pendingActivityOpenAlerts;
    _pendingActivityOpenAlerts = false;
    return open;
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
