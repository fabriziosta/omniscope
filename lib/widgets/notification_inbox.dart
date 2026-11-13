import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/shell_navigation.dart';
import '../data/notifications/app_notification.dart';
import '../data/notifications/app_notification_repository.dart';
import 'app_tooltip.dart';

/// Shell bell + unread badge that opens the stacked attention inbox.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final unread = context.watch<AppNotificationRepository>().unreadCount;

    return AppTooltip(
      message: unread == 0
          ? 'Notifications'
          : 'Notifications ($unread unread)',
      wrapDetector: true,
      child: ShadButton.ghost(
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        onPressed: () => showNotificationInbox(context),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              LucideIcons.bell,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            if (unread > 0)
              Positioned(
                top: -2,
                right: -4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.primaryForeground,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows the stacked notification inbox dialog.
Future<void> showNotificationInbox(BuildContext context) {
  return showShadDialog<void>(
    context: context,
    builder: (context) => const _NotificationInboxDialog(),
  );
}

class _NotificationInboxDialog extends StatelessWidget {
  const _NotificationInboxDialog();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final repo = context.watch<AppNotificationRepository>();
    final active = repo.active;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return ShadDialog(
      constraints: BoxConstraints(
        maxWidth: wide ? 440 : MediaQuery.sizeOf(context).width - 32,
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      title: const Text('Notifications'),
      description: Text(
        active.isEmpty
            ? 'Scheduled agent runs show up here so you can open '
                'Activity or chat to confirm or review.'
            : 'Open a pending suggestion on Activity, or chat for the rest.',
        style: theme.textTheme.muted,
      ),
      actions: [
        if (active.isNotEmpty)
          ShadButton.outline(
            onPressed: () async {
              await repo.dismissAll();
            },
            child: const Text('Dismiss all'),
          ),
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: active.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No notifications yet.',
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: active.length,
                separatorBuilder: (context, index) => Container(
                  height: 1,
                  color: theme.colorScheme.border,
                ),
                itemBuilder: (context, index) {
                  final item = active[index];
                  return _NotificationRow(item: item);
                },
              ),
            ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final repo = context.read<AppNotificationRepository>();
    final shellNav = context.read<ShellNavigationController>();
    final timeLabel = _formatClock(item.createdAt.toLocal());
    final unreadDot = !item.read;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unreadDot) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ),
              ] else
                const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.small.copyWith(
                        fontWeight:
                            item.read ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.kind.label} · $timeLabel',
                      style: theme.textTheme.muted.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              ShadButton.ghost(
                height: 44,
                onPressed: () async {
                  await repo.dismiss(item.id);
                },
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 4),
              ShadButton(
                height: 44,
                onPressed: () async {
                  await repo.markRead(item.id);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  final proposalId = item.proposalId?.trim();
                  if (proposalId != null && proposalId.isNotEmpty) {
                    shellNav.goToActivity(proposalId: proposalId);
                  } else {
                    shellNav.goToAgentChat(
                      roleId: item.roleId,
                      symbol: item.symbol,
                      notificationId: item.id,
                    );
                  }
                },
                child: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatClock(DateTime local) {
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
