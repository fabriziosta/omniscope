import 'package:flutter/foundation.dart';

/// Queued deep-link to open an agent chat (notifications, Activity, CTAs).
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
  static const marketsTabIndex = 0;
  static const portfolioTabIndex = 1;
  static const activityTabIndex = 2;
  static const agentsTabIndex = 3;
  static const settingsTabIndex = 4;

  var _tabIndex = marketsTabIndex;
  String? _pendingActivityProposalId;
  String? _pendingSettingsSectionId;
  PendingAgentChatOpen? _pendingAgentChatOpen;

  int get tabIndex => _tabIndex;

  String? get pendingActivityProposalId => _pendingActivityProposalId;

  String? get pendingSettingsSectionId => _pendingSettingsSectionId;

  PendingAgentChatOpen? get pendingAgentChatOpen => _pendingAgentChatOpen;

  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Switch to Agents tab.
  void goToAgents() {
    _tabIndex = agentsTabIndex;
    notifyListeners();
  }

  void goToActivity({String? proposalId}) {
    _pendingActivityProposalId = proposalId;
    _tabIndex = activityTabIndex;
    notifyListeners();
  }

  /// Switch to Agents and open/create a chat (e.g. from a shell notification).
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
    _tabIndex = agentsTabIndex;
    notifyListeners();
  }

  void goToSettings({String? sectionId}) {
    _pendingSettingsSectionId = sectionId;
    _tabIndex = settingsTabIndex;
    notifyListeners();
  }

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
