import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/notifications/app_notification.dart';
import 'package:omniscope/data/notifications/app_notification_repository.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppNotificationRepository', () {
    test('enqueue, unread, markRead, dismiss, dedup', () async {
      final store = await memoryConfig();
      final repo = AppNotificationRepository(store: store);
      await repo.load();

      final first = await repo.enqueue(
        AppNotification(
          id: 'n1',
          kind: AppNotificationKind.scheduledRunCompleted,
          roleId: 'marketResearch',
          createdAt: DateTime.utc(2026, 7, 1, 10),
          title: 'Scheduled run finished',
          body: 'Market Research · AAPL',
          symbol: 'AAPL',
        ),
      );
      expect(first.read, isFalse);
      expect(repo.unreadCount, 1);
      expect(repo.active, hasLength(1));

      // Same role+symbol+kind replaces rather than stacking.
      await repo.enqueue(
        AppNotification(
          id: 'n2',
          kind: AppNotificationKind.scheduledRunCompleted,
          roleId: 'marketResearch',
          createdAt: DateTime.utc(2026, 7, 1, 11),
          title: 'Scheduled run finished',
          body: 'Market Research · AAPL (again)',
          symbol: 'AAPL',
        ),
      );
      expect(repo.active, hasLength(1));
      expect(repo.active.first.id, 'n2');
      expect(repo.unreadCount, 1);

      await repo.markRead('n2');
      expect(repo.unreadCount, 0);
      expect(repo.active.first.read, isTrue);

      await repo.dismiss('n2');
      expect(repo.active, isEmpty);

      // Different kind stacks.
      await repo.enqueue(
        AppNotification(
          id: 'n3',
          kind: AppNotificationKind.scheduledProposalPending,
          roleId: 'intradayTrading',
          createdAt: DateTime.utc(2026, 7, 1, 12),
          title: 'Confirm',
          body: 'Buy 1 AAPL',
          symbol: 'AAPL',
          proposalId: 'tp1',
        ),
      );
      await repo.enqueue(
        AppNotification(
          id: 'n4',
          kind: AppNotificationKind.scheduledAutopilotDone,
          roleId: 'intradayTrading',
          createdAt: DateTime.utc(2026, 7, 1, 13),
          title: 'Autopilot',
          body: 'Buy 1 AAPL',
          symbol: 'AAPL',
          proposalId: 'tp2',
        ),
      );
      expect(repo.active, hasLength(2));
      expect(repo.unreadCount, 2);

      await repo.dismissAll();
      expect(repo.active, isEmpty);
      // Earlier dismissed n2 remains in the retained list with n3/n4.
      expect(repo.items.length, greaterThanOrEqualTo(2));

      await repo.clearAll();
      expect(repo.items, isEmpty);
    });

    test('sticky configure-Agents reminder stays unread and undismissable',
        () async {
      final store = await memoryConfig();
      final repo = AppNotificationRepository(store: store);
      await repo.load();

      expect(repo.active, isEmpty);
      expect(repo.unreadCount, 0);

      repo.setConfigureAgentsNeeded(true);
      expect(repo.active, hasLength(1));
      expect(repo.active.first.kind, AppNotificationKind.configureAgents);
      expect(repo.active.first.read, isFalse);
      expect(repo.unreadCount, 1);
      expect(repo.dismissibleActive, isEmpty);

      await repo.markRead(AppNotification.configureAgentsId);
      expect(repo.active.first.read, isFalse);
      expect(repo.unreadCount, 1);

      await repo.dismiss(AppNotification.configureAgentsId);
      expect(repo.active, hasLength(1));
      expect(repo.unreadCount, 1);

      await repo.enqueue(
        AppNotification(
          id: 'n_other',
          kind: AppNotificationKind.scheduledRunCompleted,
          roleId: 'marketResearch',
          createdAt: DateTime.utc(2026, 7, 2),
          title: 'Done',
          body: 'AAPL',
          symbol: 'AAPL',
        ),
      );
      expect(repo.active, hasLength(2));
      expect(repo.active.first.kind, AppNotificationKind.configureAgents);
      expect(repo.unreadCount, 2);
      expect(repo.dismissibleActive, hasLength(1));

      await repo.dismissAll();
      expect(repo.active, hasLength(1));
      expect(repo.active.first.kind, AppNotificationKind.configureAgents);
      expect(repo.unreadCount, 1);

      await repo.clearAll();
      expect(repo.items, isEmpty);
      expect(repo.active, hasLength(1));
      expect(repo.unreadCount, 1);

      repo.setConfigureAgentsNeeded(false);
      expect(repo.active, isEmpty);
      expect(repo.unreadCount, 0);
    });

    test('JSON round-trip via store', () async {
      final store = await memoryConfig();
      final repo = AppNotificationRepository(store: store);
      await repo.load();
      await repo.enqueue(
        AppNotification(
          id: 'persist1',
          kind: AppNotificationKind.scheduledRunFailed,
          roleId: 'marketResearch',
          createdAt: DateTime.utc(2026, 8, 1),
          title: 'Failed',
          body: 'oops',
          symbol: 'MSFT',
          chatId: 'c_sched_1',
          proposalId: 'tp_9',
        ),
      );

      final reloaded = AppNotificationRepository(store: store);
      await reloaded.load();
      expect(reloaded.active, hasLength(1));
      expect(reloaded.active.first.id, 'persist1');
      expect(
        reloaded.active.first.kind,
        AppNotificationKind.scheduledRunFailed,
      );
      expect(reloaded.active.first.chatId, 'c_sched_1');
      expect(reloaded.active.first.proposalId, 'tp_9');
    });
  });
}
