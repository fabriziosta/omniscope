import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/shell_navigation.dart';

void main() {
  group('ShellNavigationController home', () {
    test('cold start opens Home (Portfolio) tab', () {
      final nav = ShellNavigationController();
      expect(nav.tabIndex, ShellNavigationController.homeTabIndex);
      expect(nav.tabIndex, ShellNavigationController.portfolioTabIndex);
    });

    test('selectTab switches tabs', () {
      final nav = ShellNavigationController();
      nav.selectTab(ShellNavigationController.marketsTabIndex);
      expect(nav.tabIndex, ShellNavigationController.marketsTabIndex);
    });

    test('selectTab is no-op when already on that tab', () {
      final nav = ShellNavigationController();
      var notified = 0;
      nav.addListener(() => notified++);
      nav.selectTab(ShellNavigationController.homeTabIndex);
      expect(notified, 0);
      expect(nav.tabIndex, ShellNavigationController.homeTabIndex);
    });

    test('goToHome selects Home tab', () {
      final nav = ShellNavigationController();
      nav.selectTab(ShellNavigationController.agentsTabIndex);
      nav.goToHome();
      expect(nav.tabIndex, ShellNavigationController.homeTabIndex);
    });

    test('deep-links switch tabs and queue pending payloads', () {
      final nav = ShellNavigationController();
      nav.goToAgents();
      expect(nav.tabIndex, ShellNavigationController.agentsTabIndex);

      nav.goToActivity(proposalId: 'p1');
      expect(nav.tabIndex, ShellNavigationController.activityTabIndex);
      expect(nav.takePendingActivityProposalId(), 'p1');
      expect(nav.takePendingActivityOpenAlerts(), isFalse);

      nav.goToActivity(openAlerts: true);
      expect(nav.tabIndex, ShellNavigationController.activityTabIndex);
      expect(nav.takePendingActivityOpenAlerts(), isTrue);
      expect(nav.takePendingActivityOpenAlerts(), isFalse);

      nav.goToSettings(sectionId: 'connections');
      expect(nav.tabIndex, ShellNavigationController.settingsTabIndex);
      expect(nav.takePendingSettingsSectionId(), 'connections');

      nav.goToAgentChat(chatId: 'c1');
      expect(nav.tabIndex, ShellNavigationController.agentsTabIndex);
      expect(nav.takePendingAgentChatOpen()?.chatId, 'c1');
    });
  });
}
