import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/shell_navigation.dart';

void main() {
  group('ShellNavigationController landing', () {
    test('cold start shows landing on Markets tab index', () {
      final nav = ShellNavigationController();
      expect(nav.showLanding, isTrue);
      expect(nav.hasEnteredTab, isFalse);
      expect(nav.tabIndex, ShellNavigationController.marketsTabIndex);
    });

    test('selectTab hides landing and marks entered', () {
      final nav = ShellNavigationController();
      nav.selectTab(ShellNavigationController.portfolioTabIndex);
      expect(nav.showLanding, isFalse);
      expect(nav.hasEnteredTab, isTrue);
      expect(nav.tabIndex, ShellNavigationController.portfolioTabIndex);
    });

    test('selectTab while on landing with same index still dismisses', () {
      final nav = ShellNavigationController();
      expect(nav.tabIndex, ShellNavigationController.marketsTabIndex);
      nav.selectTab(ShellNavigationController.marketsTabIndex);
      expect(nav.showLanding, isFalse);
      expect(nav.hasEnteredTab, isTrue);
    });

    test('goToLanding restores landing without changing tab', () {
      final nav = ShellNavigationController();
      nav.selectTab(ShellNavigationController.agentsTabIndex);
      nav.goToLanding();
      expect(nav.showLanding, isTrue);
      expect(nav.tabIndex, ShellNavigationController.agentsTabIndex);
      expect(nav.hasEnteredTab, isTrue);
    });

    test('dismissLanding restores last tab', () {
      final nav = ShellNavigationController();
      nav.selectTab(ShellNavigationController.settingsTabIndex);
      nav.goToLanding();
      nav.dismissLanding();
      expect(nav.showLanding, isFalse);
      expect(nav.tabIndex, ShellNavigationController.settingsTabIndex);
    });

    test('deep-links clear landing', () {
      final nav = ShellNavigationController();
      nav.goToAgents();
      expect(nav.showLanding, isFalse);
      expect(nav.tabIndex, ShellNavigationController.agentsTabIndex);

      nav.goToLanding();
      nav.goToActivity(proposalId: 'p1');
      expect(nav.showLanding, isFalse);
      expect(nav.tabIndex, ShellNavigationController.activityTabIndex);
      expect(nav.takePendingActivityProposalId(), 'p1');

      nav.goToLanding();
      nav.goToSettings(sectionId: 'connections');
      expect(nav.showLanding, isFalse);
      expect(nav.tabIndex, ShellNavigationController.settingsTabIndex);
      expect(nav.takePendingSettingsSectionId(), 'connections');

      nav.goToLanding();
      nav.goToAgentChat(chatId: 'c1');
      expect(nav.showLanding, isFalse);
      expect(nav.tabIndex, ShellNavigationController.agentsTabIndex);
      expect(nav.takePendingAgentChatOpen()?.chatId, 'c1');
    });
  });
}
